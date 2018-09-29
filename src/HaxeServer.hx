import python.lib.subprocess.Popen;
import python.lib.io.FileIO;
import python.lib.Queue;
import python.lib.threading.Thread;
import haxe.io.Bytes;

using StringTools;

typedef BuildOutput = {
	message: String,
	hasError: Bool,
	log: Array<String>
}

typedef AsyncHandle = {
	isRunning: Void -> Bool,
	cancel: Void -> Void,
}

// https://haxe.org/manual/cr-completion-overview.html
@:enum abstract DisplayMode(String) to String {
	var Field = '';

	var Usage = 'usage';
	var Position = 'position';
	var Toplevel = 'toplevel';
	var Type = 'type';
	var Signature = 'signature';
	var Package = 'package';

	// Unknown modes, see tests
	// https://github.com/HaxeFoundation/haxe/tree/master/tests/display/src/cases
	// And --display argument handling https://github.com/HaxeFoundation/haxe/blob/master/src/display/displayOutput.ml#L643
	// @resolve@A https://github.com/HaxeFoundation/haxe/issues/2996
	// @type
	// @package
	// @signature https://github.com/HaxeFoundation/haxe/pull/4758
	// @module-symbols
	// @rename and @references? may not be enabled?
}

@:enum abstract HaxeServerMode<T>(Int) {
	var Stdio:HaxeServerMode<HaxeServerStdio> = 0;
}

interface HaxeServer {

	function restart(): Void;
	function terminate(): Void;
	function buildAsync(hxml: String, onComplete: BuildOutput -> Void, ?timeout_s: Int): AsyncHandle;

}

class HaxeServerStdio implements HaxeServer {

	var processUserArgs = new Array<String>();
	var process: Popen;
	var processWriteLock = new python.lib.threading.Lock();

	// thread safe queue 
	var errQueue: Queue;

	public function new(?args: Array<String>){
		if (args != null) {
			processUserArgs = args;
		}
		start(processUserArgs);
	}

	// python destructor
	@:native('__del__')
	@:keep
	function __del__(){
		// kill server if running
		terminate();
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
		errQueue = createServerMessageQueue(process.stderr);

		var haxeVersionString = execute('-version', 1.5).toString();
		trace('Haxe server started: $haxeVersionString');
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
			trace('Stopping haxe server');
			process.terminate();
		}
		process = null;
		errQueue = null;
	}

	/**
		Build asynchronously
	**/
	public function buildAsync(hxml: String, onComplete: BuildOutput -> Void, ?timeout_s: Int): AsyncHandle {
		var cancelled = false;

		function buildCallback() {
			var result = build(hxml, timeout_s);
			if (!cancelled) {
				onComplete(result);
			}
		}

		var buildThread = new Thread({target: buildCallback});
		buildThread.start();

		return {
			isRunning: buildThread.is_alive,
			cancel: function() {
				cancelled = true;
			},
		}
	}

	public function display(hxml: String, filePath: String, location: Int, mode: String, details: Bool, ?fileContent: String) {
		// -D use-rtti-doc "Allows access to documentation during compilation"
		// -D display-details "each field additionally has a k attribute which can either be var or method. This allows distinguishing method fields from variable fields that have a function type."
		// -D display-stdin "Read the contents of a file specified in --display from standard input"
		var timeout_s = 1.5;

		var modeString = mode == null ? '' : '@$mode';

		var displayDirectives = '';

		if (details) {
			displayDirectives += '\n-D display-details';
		}

		if (fileContent != null) {
			displayDirectives += '\n-D display-stdin';
		}

		displayDirectives += '\n--display "$filePath"@$location$modeString';

		if (fileContent != null) {
			displayDirectives += '\n' + String.fromCharCode(0x01) + fileContent;
		}

		var result = execute(hxml + displayDirectives, timeout_s).toString();

		// as an optimization we assume the result includes non-xml content when the first character is not a '<'
		if (result.fastCodeAt(0) != '<'.fastCodeAt(0)){
			return parseCompilerOutput(result);
		}

		return {
			message: result,
			hasError: false,
			log: []
		}
	}

	/**
		Build synchronously
	**/
	function build(hxml: String, ?timeout_s = 120) {
		var result = execute(hxml, timeout_s).toString();
		return parseCompilerOutput(result);
	}

	function execute(hxml: String, ?timeout_s: Float): haxe.io.Bytes {
		var buffer = new haxe.io.BytesBuffer();
		buffer.addString('\n' + hxml + '\n');

		// create stdin payload by prepending the buffer length
		var bytes = buffer.getBytes();
		var length = bytes.length;
		var payloadBytes = Bytes.alloc(4 + length);
		payloadBytes.setInt32(0, length);
		payloadBytes.blit(4, bytes, 0, length);

		var result = null;

		// lock writing to the process until it's returns results
		processWriteLock.acquire();
		{
			// trace('Writing buffer: ', payloadBytes.getData());
			// if there was an timeout or an exception reading previous message, there will be residual junk in the queue
			// clear it before sending new payloads
			
			// @! we should probably track unread messages (messages that timeout when reading) and wait on consuming them here and contribute the time required to the timeout
			// additionally, we should restart the server if we're waiting too long
			try {
				while(true) errQueue.get(false); // pop queue until empty
			}
			catch (e: python.lib.Queue.Empty) {}
			catch (e: Dynamic) {
				trace("Unknown error reading from queue: $e");
			}

			process.stdin.write(payloadBytes.getData());
			process.stdin.flush();

			// @! if this times-out it will throw – it might be better to catch it and return null instead
			try {
				result = errQueue.get(true, timeout_s);
			} catch (e: python.lib.Queue.Empty) {
				trace("Error: errQueue is unexpectedly empty");
			} catch (e: Dynamic) {
				trace("Unknown error reading from queue: $e");
			}
		}
		processWriteLock.release();

		if (result == null) {
			throw "Unable to read output from haxe compiler";
		}
		
		return result;
	}

	static function parseCompilerOutput(outputString: String) {
		var lines = outputString.toString().split('\n');

		var hasError = false;
		var log = [];
		var message = [];

		for (line in lines) {
			switch line.fastCodeAt(0) {
				case 0x01:
					log.push(line.substr(1).replace('\x01', '\n').rtrim()); // trim trailing newlines
				case 0x02:
					hasError = true;
				default:
					message.push(line);
			}
		}

		return {
			message: message.join('\n'),
			hasError: hasError,
			log: log
		}
	}

	static function createServerMessageQueue(pipe: FileIO) {
		function enqueueMessages(pipe: FileIO, queue: Queue){
			while(true) {
				var lengthHeader = haxe.io.Bytes.ofData(pipe.read(4));
				if (lengthHeader == null || lengthHeader.length != 4) {
					trace('Pipe finished (case A)');
					break; // pipe finished
				}
				var bytesRemaining = lengthHeader.getInt32(0);
				var messageBuffer = new haxe.io.BytesBuffer();
				trace('Reading message ($bytesRemaining bytes)');

				// may not be complete message
				var pipeDead: Bool = false;
				while (bytesRemaining > 0) {
					var pipeBytes = haxe.io.Bytes.ofData(pipe.read(bytesRemaining));

					if (pipeBytes == null) {
						pipeDead = true;
						trace('Pipe finished (case B - message was null)');
						break; // pipe finished
					} else {
						bytesRemaining -= pipeBytes.length;
						if (bytesRemaining > 0) {
							trace('\tread chunk of ${pipeBytes.length} bytes');
						}
						messageBuffer.add(pipeBytes);
					}
				}

				if (pipeDead) {
					break;
				}

				// message has been read at this point
				
				// error check
				if (bytesRemaining == 0) {
					var messageBytes = messageBuffer.getBytes();
					trace('Message read successfully');
					trace('"$messageBytes"');
					queue.put(messageBytes);
				} else {
					// bytesRemaining
					throw 'Unexpected number of bytes return from pipe';
				}
			}

			pipe.close();
		}

		var queue = new Queue();

		var messageReaderThread = new Thread({
			target: enqueueMessages,
			args: new python.Tuple<Any>([pipe, queue]),
			daemon: true
		});

		messageReaderThread.start();

		return queue;
	}

}