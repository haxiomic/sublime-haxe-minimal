import HaxeServer;

class HaxeProject {

	// may throw if the process fails to start
	static var haxeServerStdioHandle: HaxeServerStdio = null;
	static var haxeServerSocketHandle: HaxeServer = null;

	static public inline function getHaxeServerHandle<T>(view: sublime.View, mode: HaxeServerMode<T>): T {
		switch mode {
			case Stdio:
				if (haxeServerStdioHandle == null) {
					haxeServerStdioHandle = new HaxeServerStdio();
				}
				return haxeServerStdioHandle;
			default:
				throw 'Not yet supported';
		}

	}

	static public function terminateHaxeServers() {
		if (haxeServerStdioHandle != null) {
			haxeServerStdioHandle.terminate();
			haxeServerStdioHandle = null;
		}
		if (haxeServerSocketHandle != null) {
			haxeServerSocketHandle.terminate();
			haxeServerSocketHandle = null;
		}
	}

	/**
		@!todo
			- split --next and handle --each
			- determine which blocks of hxml are needed for a given view
		Returns hxml string required to build this view (including --cwd directive)
		If a hxml file has multiple outputs separated by --next, only use the first that involves view
		returns null if no hxml files were found
	**/
	static public function getHxmlForView(view: sublime.View): String {
		var hxmlPath = findAssociatedHxmlPath(view);

		if (hxmlPath != null) {
			var cwd = Path.directory(hxmlPath);
			return '--cwd "$cwd"\n' + sys.io.File.getContent(hxmlPath);
		}

		return generateHxmlForView(view);
	}

	/**
		@!todo
		When a view has no associated hxml file we can try to produce some arguments to enable autocompletion and --interp
	**/
	static public function generateHxmlForView(view: sublime.View) {
		var hxml = '\n--no-output';
		if (view.file_name() != null) {
			hxml += '\n--cwd ${Path.directory(view.file_name())}';
			hxml += '\n${Path.withoutDirectory(view.file_name())}';
		}
		return hxml;
	}
	
	/**
		@!todo
		Searches and returns the absolute path of a hxml file that may be used to build compile a view or null if no hxml path can be found
	**/
	static public function findAssociatedHxmlPath(view: sublime.View): String {

		// search local and parent directories for hxml files
		if (view.file_name() != null) {
			var maxDepth = 4;
			var searchDir = Path.directory(view.file_name());

			for(i in 0...maxDepth) {
				if (searchDir == '') break;
				var files = sys.FileSystem.readDirectory(searchDir);
				for (f in files) {
					if (Path.extension(f).toLowerCase() == 'hxml') {
						// found a hxml file
						var hxmlPath = Path.join([searchDir, f]);
						if (validateHxmlForView(view, hxmlPath)) {
							return hxmlPath;
						}
					}
				}

				// use the parent directory for the next loop
				var parentSearchDir = Path.directory(searchDir);
				// can't search higher
				if (parentSearchDir == searchDir) return null;
				searchDir = parentSearchDir;
			}
		}

		return null;
	}

	/**
		@!todo
	**/
	static function validateHxmlForView(view: sublime.View, hxmlPath: String) {
		// @! can we determine if this hxml file will compile the view?
		return true;
	}

}