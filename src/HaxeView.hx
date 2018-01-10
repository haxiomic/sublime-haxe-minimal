import python.lib.io.FileIO;

class HaxeView extends sublime_plugin.ViewEventListener {

	// var tempFileHandle: FileIO;

	static inline var HAXE_STATUS = 'haxe_status';

	override function on_modified() {
	}

	override function on_close() {
		// perform clean up of local state
		// the temp file is automatically deleted on close
		// if (tempFileHandle != null) {
			// tempFileHandle.close();
			// tempFileHandle = null;
		// }
	}

	override function on_post_save_async() {
		// build using the project hxml associated with the view
		// there may be no hxml file to find, in which case, use some sensible default build arguments
	}

	override function on_query_completions(prefix:String, locations:Array<Int>):Null<haxe.extern.EitherType<Array<Any>, python.Tuple<Any>>> {
		var hxml = HaxeProject.getHxmlForView(view);

		if (hxml == null) {
			view.set_status(HAXE_STATUS, 'Could not find hxml for autocomplete');
			return null;
		}

		var viewContent = view.substr(new sublime.Region(0, view.size()));
		var haxeServer = HaxeProject.getHaxeServerHandle(view, Stdio);

		var filePath = view.file_name();
		haxeServer.display(hxml, view.file_name(), locations[0], 'toplevel', viewContent);

		//@! we should ensure we perform at least 1 full build before using autocomplete for cache performance
	
			/*
		
		if (viewFilePath != null && hxmlPath != null) {
			// var tempFilePath = copyContentToTempFile(Path.directory(viewFilePath));

			if (hxmlPath == null) return null;

			var cwd = Path.directory(hxmlPath);

			var displayMode = '@toplevel';
			Compiler.buildOnServer(
				[
					hxmlPath,
					'--cwd', cwd,
					'-D', 'display-details',
					'--display', '"$viewFilePath"@${locations[0]}$displayMode'
				],
				6000,
				false,
				function(stdout, stderr) {
					trace('on_query_completions $stdout -- $stderr');
				},
				function(code, msg) {
					trace('on_query_completions $code $msg');
				}
			);
		}
			*/

		return null;
	}

	/*
	var _tempFileChangeCount:Int = -1;
	function copyContentToTempFile(directory: String): String {
		// clear old temp file if it's in the wrong directory
		if (tempFileHandle != null) {
			if (Path.directory(tempFileHandle.name) != directory) {
				tempFileHandle.close();
				tempFileHandle = null;
			}
		}

		if (tempFileHandle == null) {
			// this temporary file will automatically delete itself when closed
			tempFileHandle = python.lib.Tempfile.NamedTemporaryFile(
				'w',
				-1,
				'utf-8',
				null,
				'.hx', // suffix
				'__${HaxePlugin.id}__', // prefix
				directory, // directory
				true // delete on close
			);
			_tempFileChangeCount = -1;
			trace('Created temporary file ${tempFileHandle.name}');
		}

		// write contents to file if the file has changed since last writing it
		var currentChangeCount = view.change_count();
		if (_tempFileChangeCount != currentChangeCount) {
			var viewContent = view.substr(new sublime.Region(0, view.size()));
			tempFileHandle.seek(0, SeekSet);
			tempFileHandle.truncate(0);
			tempFileHandle.write(untyped viewContent); // string -> bytes conversion is handled automatically controlled by the file encoding
			tempFileHandle.flush();
			_tempFileChangeCount = view.change_count();
		}

		return tempFileHandle.name;
	}
	*/

	static function is_applicable(settings: sublime.Settings) {
		return settings.get('syntax') == 'Packages/Haxe Minimal/syntax/haxe.tmLanguage';
	}

	static function applies_to_primary_view_only() return false;

}