import sys.io.Process;
import python.lib.subprocess.Popen;
import python.lib.io.FileIO;
import python.lib.io.IOBase;
import python.lib.Queue;
import python.lib.threading.Thread;
import haxe.io.Bytes;

using StringTools;

typedef HaxeOutput = {
	output: String,
	hasError: Bool
}

typedef AsyncHandle = {
	cancel: Void -> Void
}

// https://haxe.org/manual/cr-completion-overview.html
@:enum abstract CompletionMode(String) to String {
	var Usage = 'usage';
	var Position = 'position';
	var Toplevel = 'toplevel';
}

@:enum abstract HaxeServerMode<T>(Int) {
	var Stdio:HaxeServerMode<HaxeServerStdio> = 0;
}

interface HaxeServer {

	function restart(): Void;
	function terminate(): Void;
	function buildAsync(hxml: String, onComplete: HaxeOutput -> Void, ?handleLog: String -> Void): AsyncHandle;

}

class HaxeServerStdio implements HaxeServer {

	var processUserArgs = new Array<String>();
	var process: Popen;
	var processWriteLock = new python.lib.threading.Lock();

	var haxeVersionString: String;

	// thread safe queue 
	var errQueue: Queue;

	public function new(?args: Array<String>){
		if (args != null) {
			processUserArgs = args;
		}
		start(processUserArgs);
	}

	function start(args: Array<String>) {
		var sys = python.lib.Sys;
		var moduleNames: python.Tuple<String> = untyped sys.builtin_module_names;
		var isPosix = moduleNames.toArray().indexOf('posix') != -1;

		trace('Starting haxe server');
		process = Popen.create(
			['haxe', '--wait', 'stdio'].concat(args),
			{
				stdout: python.lib.Subprocess.PIPE,
				stderr: python.lib.Subprocess.PIPE,
				stdin: python.lib.Subprocess.PIPE,
				close_fds: isPosix
			}
		);

		var exitCode = process.poll();

		// process exited while starting
		if (exitCode != null) {
			var errorMessage = process.stderr.readall().decode('utf-8');
			throw 'Haxe server failed to start: ($exitCode) $errorMessage';
		}

		// create an non-blocking queues we can read from
		errQueue = createIOQueue(process.stderr);

		haxeVersionString = execute('-version', 3).output;
	}

	/**
		Terminate the current server and start a new instance
	**/
	public function restart() {
		terminate();
		start(processUserArgs);
	}

	/**
		Terminate process
		When terminated no other methods should be called until the processes has been restarted with .restart()
	**/
	public function terminate() {
		if (process != null) {
			process.terminate();
		}
		process = null;
		errQueue = null;
		haxeVersionString = null;
	}

	/**
		Build asynchronously
	**/
	public function buildAsync(hxml: String, onComplete: HaxeOutput -> Void, ?handleLog: String -> Void): AsyncHandle {
		var cancelled = false;
		function buildCallback() {
			var result = build(hxml, handleLog);
			if (!cancelled) {
				onComplete(result);
			}
		}

		var buildThread = new Thread({target: buildCallback});
		buildThread.start();
		return {
			cancel: function() {
				cancelled = true;
			}
		}
	}

	public function display(hxml: String, filePath: String, location: Int, ?mode: String, ?fileContent: String) {
		// -D use-rtti-doc "Allows access to documentation during compilation"
		// -D display-details "each field additionally has a k attribute which can either be var or method. This allows distinguishing method fields from variable fields that have a function type."
		// -D display-stdin "Read the contents of a file specified in --display from standard input"
		var timeout_s = 1.5;

		var modeString = mode == null ? '' : '@$mode';

		var displayDirectives = '';
		displayDirectives += '\n-D display-details';

		if (fileContent != null) {
			displayDirectives += '\n-D display-stdin';
		}

		displayDirectives += '\n--display "$filePath"@$location$modeString';

		if (fileContent != null) {
			displayDirectives += '\n' + String.fromCharCode(0x01) + fileContent;
		}

		var result = execute(hxml + displayDirectives, timeout_s);
		// trace(result);
	}

	/**
		Build synchronously
	**/
	function build(hxml: String, ?handleLog: String -> Void) {
		var timeout_s = 120;

		// hack: print version as the last line so we always get some output
		hxml = hxml += '\n--next\n-version';
		var result = execute(hxml, timeout_s, handleLog);
		// strip last instance of version string (which should be the haxe version string we added)
		var versionStart = result.output.lastIndexOf(haxeVersionString);
		var versionEnd = versionStart + haxeVersionString.length;
		result.output = result.output.substring(0, versionStart) + result.output.substring(versionEnd);

		return result;
	}

	// be aware: if haxe produces no response (as in the case of a successful compile) then this will hang and throw
	function execute(hxml: String, ?timeout_s: Float, ?handleLog: String -> Void) {
		var buffer = new haxe.io.BytesBuffer();
		buffer.addString('\n' + hxml + '\n');

		// create stdin payload by prepending the buffer length
		var bytes = buffer.getBytes();
		var length = bytes.length;
		var payloadBytes = Bytes.alloc(4 + length);
		payloadBytes.setInt32(0, length);
		payloadBytes.blit(4, bytes, 0, length);

		// lock writing to the process until it's returns results
		processWriteLock.acquire();
		trace('Writing buffer: ', payloadBytes.getData());
		// if there was an timeout or an exception reading previous message, there will be residual junk in the queue
		try {
			while(true) errQueue.get(false); // pop queue until empty
		} catch (e: python.lib.Queue.Empty) {}
		// @! maybe we should ensure the ioQueue is empty at this point - junk may be left from previous executions if the timeout was reached
		process.stdin.write(payloadBytes.getData());
		var result = readServerMessage(errQueue, timeout_s, handleLog);
		processWriteLock.release();
		
		return result;
	}

	/**
		Synchronously wait on the ioQueue to read replies from the haxe server
		Line format must conform to:
			[payload length 4 byte LE int][payload]
	**/
	static function readServerMessage(ioQueue: Queue, ?timeout_s: Float, ?handleLog: String -> Void): HaxeOutput {
		// now block and wait for lines written to stderr to read a complete message
		// if we timeout we enter an unknown state and will probably need to restart the server
		var messageBuffer = new haxe.io.BytesOutput();
		var hasError = false;
		var bytesRemaining = 0;
		var messageEncodingError = false;
		try {
			while(true) {
				var line: python.Bytearray = ioQueue.get(true, timeout_s);
				var messageChunk: Bytes = null;

				var bytes = Bytes.ofData(line);
				if (bytesRemaining <= 0) {
					if (bytes.length < 4) {
						// bad message, there isn't a length header
						throw 'Haxe server replied with an invalid message';
						break;
					}
					// read expected message length
					bytesRemaining = bytes.getInt32(0);
					trace('bytesRemaining', bytesRemaining);
					messageBuffer.prepare(bytesRemaining);
					// strip the first 4 bytes (32 bit int)
					messageChunk = bytes.sub(4, bytes.length - 4);
				} else {
					messageChunk = bytes;
				}

				bytesRemaining -= messageChunk.length;

				// append message
				switch messageChunk.get(0) {
					// 0x01 means print debug line
					case 0x01:
						var logLine = messageChunk.toString().substr(1).replace('\x01', '\n');
						// remove the last character (an unwanted \n)
						logLine = logLine.substr(0, logLine.length - 1);
						if (handleLog != null) {
							handleLog(logLine);
						} else {
							untyped print('Haxe > ' + logLine.rtrim());
						}

					case 0x02:
						hasError = true;

					 default:
					 	messageBuffer.writeFullBytes(messageChunk, 0, messageChunk.length);
				}

				if (bytesRemaining == 0) break; // message was read
				if (bytesRemaining < 0) {
					messageEncodingError = true;
					throw 'Haxe server message contained more bytes than expected';
				}
			}
		} catch (e: python.lib.Queue.Empty) {
			messageEncodingError = true;
			// this may happen if the queue contains less bytes than expected given the message length header
			throw 'Queue was empty but there are $bytesRemaining bytes unaccounted for';
		}

		var messageBytes = messageBuffer.getBytes();

		return {
			output: messageBytes.toString(),
			hasError: hasError,
		};
	}

	static function createIOQueue(stdio: IOBase) {
		function enqueueLines(out: IOBase, queue: Queue){
			var line: python.Bytearray;
			while((line = untyped out.readline()).length > 0){
				// trace('EQ>"$line"');
				queue.put(line);
			}
			trace('EQ closed');
			out.close();
		}

		var queue = new Queue();

		var lineReaderThread = new Thread({
			target: enqueueLines,
			args: new python.Tuple<Any>([stdio, queue]),
			daemon: true
		});

		lineReaderThread.start();

		return queue;
	}

}