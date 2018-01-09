class HaxeProject {
	
	// returns absolute path of hxml file that may be used to build compile a view
	// returns null if no hxml path can be found
	static public function findAssociatedHxmlPath(view: sublime.View): String {

		// search local and parent directories for hxml files
		if (view.file_name() != null) {
			var maxDepth = 4;
			var searchDir = Path.directory(view.file_name());

			for(i in 0...maxDepth) {
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

	static function validateHxmlForView(view: sublime.View, hxmlPath: String) {
		// @! can we determine if this hxml file will compile the view?
		return true;
	}

}