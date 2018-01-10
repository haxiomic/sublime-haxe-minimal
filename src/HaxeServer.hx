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

class HaxeServer {

	var processUserArgs = new Array<String>();
	var process: Popen;
	var processWriteLock = new python.lib.threading.Lock();

	var errQueue: Queue; // thread safe
	var haxeVersionString: String;

	public function new(?args: Array<String>){
		if (args != null) {
			processUserArgs = args;
		}
		start(processUserArgs);
	}

	function start(args: Array<String>) {
		var sys = python.lib.Sys;
		// var isPosixSystem = untyped sys.builtin_module_names.indexOf('POSIX') != -1;
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

		haxeVersionString = execute(['-version'], 3).output;
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
	public function buildAsync(hxmlLines: Array<String>, onComplete: HaxeOutput -> Void, ?handleLog: String -> Void) {
		function buildCallback() {
			onComplete(build(hxmlLines, handleLog));
		}

		var buildThread = new Thread({target: buildCallback});
		buildThread.start();
	}

	/**
		Build synchronously
	**/
	function build(hxmlLines: Array<String>, ?handleLog: String -> Void) {
		var timeout_s = 120;

		// hack: print version as the last line so we always get some output
		hxmlLines = hxmlLines.concat(['--next', '-version']);
		var result = execute(hxmlLines, timeout_s, handleLog);
		// strip last instance of version string (which should be the haxe version string we added)
		var versionStart = result.output.lastIndexOf(haxeVersionString);
		var versionEnd = versionStart + haxeVersionString.length;
		result.output = result.output.substring(0, versionStart) + result.output.substring(versionEnd);

		return result;
	}

	// be aware: if haxe produces no response (as in the case of a successful compile) then this will hang and throw
	function execute(hxmlLines: Array<String>, ?timeout_s: Float, ?handleLog: String -> Void) {
		var buffer = new haxe.io.BytesBuffer();
		buffer.addString('\n' + hxmlLines.join('\n') + '\n');

		// create stdin payload by prepending the buffer length
		var bytes = buffer.getBytes();
		var length = bytes.length;
		var payloadBytes = Bytes.alloc(4 + length);
		payloadBytes.setInt32(0, length);
		payloadBytes.blit(4, bytes, 0, length);

		// lock writing to the process until it's returns results
		processWriteLock.acquire();
		trace('Writing buffer: ', payloadBytes.getData());
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
		var output = '';
		var hasError = false;
		try {
			var bytesRemaining = 0;
			while(true) {
				var line: python.Bytearray = ioQueue.get(true, timeout_s);
				var messageBytes: Bytes = null;

				var bytes = Bytes.ofData(line);
				if (bytesRemaining <= 0) {
					if (bytes.length < 4) {
						// bad message, there isn't a length header
						throw 'Haxe server replied with an invalid message';
						break;
					}
					// read expected message length
					bytesRemaining = bytes.getInt32(0);
					// strip the first 4 bytes (32 bit int)
					messageBytes = bytes.sub(4, bytes.length - 4);
				} else {
					messageBytes = bytes;
				}

				bytesRemaining -= messageBytes.length;

				// append message
				switch messageBytes.get(0) {
					// 0x01 means print debug line
					case 0x01:
						var logLine = messageBytes.toString().substr(1).replace('\x01', '\n');
						// remove the last character (an unwanted \n)
						logLine = logLine.substr(0, logLine.length - 1);
						if (handleLog != null) {
							handleLog(logLine);
						} else {
							untyped print('Haxe > ' + logLine.rtrim());
						}
					case 0x02: hasError = true;
					  default: output += messageBytes.toString();
				}

				if (bytesRemaining == 0) break;
				if (bytesRemaining < 0) {
					throw 'Haxe server message contained more bytes than expected';
				}
			}
		} catch (e: python.lib.Queue.Empty) {
			// this may happen if the queue contains less bytes than expected given the message length header
			throw 'Haxe server message queue was empty - either haxe took too long to generate the message or the message data was shorter than the header specified';
		}

		return {
			output: output,
			hasError: hasError,
		};
	}

	static function createIOQueue(stdio: IOBase) {
		function enqueueLines(out: IOBase, queue: Queue){
			var line: python.Bytearray;
			while((line = untyped out.readline()).length > 0){
				queue.put(line);
			}
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