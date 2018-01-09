import sys.io.Process;
import python.lib.subprocess.Popen;
import python.lib.io.FileIO;
import python.lib.io.IOBase;
import python.lib.Queue;
import python.lib.threading.Thread;
import haxe.io.Bytes;

class HaxeServer {

	static var process: Popen; 

	static public function start(
		?args: Array<String>,
		?onStarted: Void -> Void,
		?onError: String -> Void
	) {
		trace('HaxeServer.start()');
		args = args == null ? [] : args;

		try {
			var sys = python.lib.Sys;
			// var isPosixSystem = untyped sys.builtin_module_names.indexOf('POSIX') != -1;
			var moduleNames: python.Tuple<String> = untyped sys.builtin_module_names;
			var isPosix = moduleNames.toArray().indexOf('posix') != -1;

			var popen = Popen.create(
				['haxe', '--wait', 'stdio'].concat(args),
				{
					stdout: python.lib.Subprocess.PIPE,
					stderr: python.lib.Subprocess.PIPE,
					stdin: python.lib.Subprocess.PIPE,
					close_fds: isPosix
				}
			);

			var exitCode = popen.poll();

			// process exited while starting
			if (exitCode != null) {
				throw 'Haxe server failed to start ($exitCode)';
			}

			// when using --wait stdio, haxe communicates via stderr
			// create an non-blocking ioQueue we can read from
			var ioQueue = createIOQueue(popen.stderr);

			// test
			trace('Result: "${execute(popen, ioQueue, ['-version'])}"');

			// test terminate
			sublime.Sublime.set_timeout_async(function(?_) {
				popen.terminate();
			}, 2000);

		}catch(e:Any) {
			if (onError != null) onError(Std.string(e));
			return;
		}
	}

	static function stop() {
		process.terminate();
	}

	static function createIOQueue(stdio: IOBase) {
		function enqueueLines(out: IOBase, queue: Queue){
			trace('enqueueLines $out');
			var line: python.Bytearray;
			while((line = untyped out.readline()).length > 0){
				trace('Enqueue thread line ($out):', line);
				queue.put(line);
			}
			out.close();
			trace('Enqueue thread closed $out');
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

	static function execute(popen: Popen, ioQueue: Queue, args: Array<String>) {
		var buffer = new haxe.io.BytesBuffer();
		buffer.addString('\n' + args.join('\n'));

		// create stdin payload by prepending the buffer length
		var bytes = buffer.getBytes();
		var length = bytes.length;
		var payloadBytes = Bytes.alloc(4 + length);
		payloadBytes.setInt32(0, length);
		payloadBytes.blit(4, bytes, 0, length);

		trace('Writing buffer: ', payloadBytes.getData());
		popen.stdin.write(payloadBytes.getData());
		popen.stdin.flush();

		// now block and wait for lines written to stderr to read a complete message
		// if we timeout we enter an unknown state and will probably need to restart the server
		var message = '';
		try {
			var bytesRemaining = 0;
			while(true) {
				var line: python.Bytearray = ioQueue.get(true, 0.3);
				var messageBytes: Bytes = null;

				var bytes = Bytes.ofData(line);
				if (bytesRemaining <= 0) {
					// read expected message length
					bytesRemaining = bytes.getInt32(0);
					// strip the first 4 bytes (32 bit int)
					messageBytes = bytes.sub(4, bytes.length - 4);
				} else {
					messageBytes = bytes;
				}

				// append message
				message += messageBytes.toString();
				bytesRemaining -= messageBytes.length;

				if (bytesRemaining == 0) break;
				if (bytesRemaining < 0) {
					throw 'Message contained more bytes than expected';
				}
			}
		} catch (a: Any) {
			trace('Queue is empty'); // this implies we over-read
		}

		return message;
	}

}