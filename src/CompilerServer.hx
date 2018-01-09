import sys.io.Process;

class CompilerServer {
	
	static public function touchServer(
		port: Int,
		onRunning: Void -> Void, 
		onError: String -> Void
	) {
		if (isServerRunning(port)) {
			trace('Compiler server is running');
			onRunning();
		} else {
			startServerAsync(port, onRunning, onError);
		}
	}

	static public function isServerRunning(port: Int) {
		var process = new Process('haxe', ['--connect', '$port']);
		var exitCode = process.exitCode(true);
		return exitCode == 0;
	}

	static function startServerAsync(
		port: Int,
		onStarted: Void->Void,
		onError: String->Void
	) {
		trace('Starting Compiler server on port $port');

		var popen = python.lib.subprocess.Popen.create(
		    ['haxe', '--wait', '$port'],
		    {
		    	stdout: python.lib.Subprocess.PIPE,
		    	stderr: python.lib.Subprocess.PIPE
		    }
		);

		var pollInterval_ms = 16;

		function pollLoop() {
			var exitCode = popen.poll();
			if (exitCode == null) {
				// process is running
				if (isServerRunning(port)) {
					onStarted();
				} else {
					// process is probably starting up
					// wait a little longer and poll again
					sublime.Sublime.set_timeout_async(function(?_) pollLoop(), pollInterval_ms);
				}
			} else {
				// process has exited
				// to be able to read the stdout/stderr we need a separate thread to buffer it
				// implementation here
				onError('Unknown error');
			}
		}

		pollLoop();
	}

}