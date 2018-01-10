import sys.io.Process;
import python.lib.subprocess.Popen;
import python.lib.io.FileIO;
import python.lib.io.IOBase;
import python.lib.Queue;
import python.lib.threading.Thread;
import haxe.io.Bytes;

class HaxeServer {

	var process: Popen; 
	var errQueue: Queue;

	public function new(?args: Array<String>){
		args = args == null ? [] : args;

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
	}

	public function build(hxmlLines: Array<String>) {
		var buffer = new haxe.io.BytesBuffer();
		buffer.addString('\n' + hxmlLines.join('\n'));

		// hack: print version as the last line so we always get some output
		buffer.addString('\n--next\n-version');

		// create stdin payload by prepending the buffer length
		var bytes = buffer.getBytes();
		var length = bytes.length;
		var payloadBytes = Bytes.alloc(4 + length);
		payloadBytes.setInt32(0, length);
		payloadBytes.blit(4, bytes, 0, length);

		trace('Writing buffer: ', payloadBytes.getData());
		process.stdin.write(payloadBytes.getData());

		var timeout_s = 1;
		var message = readServerMessage(errQueue, timeout_s);

		// @! todo: strip last line (haxe version)
	}

	function terminate() {
		process.terminate();
		process = null;
		errQueue = null;
	}

	static function readServerMessage(ioQueue: Queue, timeout_s: Float) {
		// now block and wait for lines written to stderr to read a complete message
		// if we timeout we enter an unknown state and will probably need to restart the server
		var message = '';
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
					trace('bytesRemaining: $bytesRemaining');
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
					throw 'Haxe server message contained more bytes than expected';
				}
			}
		} catch (e: python.lib.Queue.Empty) {
			// this may happen if we execede
			throw 'Haxe server message queue was empty - either haxe took too long to generate the message or the message data was shorter than the header specified';
		}

		return message;
	}

	static function createIOQueue(stdio: IOBase) {
		function enqueueLines(out: IOBase, queue: Queue){
			trace('Enqueue thread started ($out)');
			var line: python.Bytearray;
			while((line = untyped out.readline()).length > 0){
				trace('Enqueue thread line ($out):', line);
				queue.put(line);
			}
			out.close();
			trace('Enqueue thread ended ($out)');
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