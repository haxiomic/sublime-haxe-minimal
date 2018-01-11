// WindowCommand.run() takes different named arguments depending on the variants
// This class redefines run to include the extra arguments
@:pythonImport("sublime_plugin", "WindowCommand") private extern class VariantsWindowCommand extends sublime_plugin.WindowCommand {
	override function new(window:sublime.Window);
	override function run(?args:python.Dict<String, Any>, ?run_after_build: Bool): Void;
}

class HaxeBuildCommand extends VariantsWindowCommand {

	var panel: sublime.View;
	var panelLock = new python.lib.threading.Lock();

	var buildHandle = null;

	override function is_enabled(?args:python.Dict<String, Any>):Bool {
		if (args != null && args.get('kill') == true) {
			// return true if process is running - this will enable the cancel command
			return false;
		}
		if (args != null && args.get('run_after_build') == true) {
			// should add --interp argument
			return false;
		}
		return true;
	}

	override function is_visible(?args:python.Dict<String, Any>) {
		return is_enabled(args);
	}

	override function run(?args:python.Dict<String, Any>, ?run_after_build: Bool = false):Void {
		if (args != null && args.get('kill') == true) {
			trace('@! todo: implement cancel build');
			return;
		}

		// we can access some useful window variables including the root folder of the active file
		// var vars = window.extract_variables();

		var view = window.active_view();

		clearBuildStatus(view);
		clearResultsPanel();

		// determine compiler args
		var hxmlContent: String = null;
		switch (view.settings().get('syntax'): String) {
			case 'Packages/Haxe Minimal/syntax/hxml.tmLanguage':
				var hxmlPath = view.file_name();

				if (hxmlPath == null) {
					// could not build because the file hasn't been saved
					appendPanel('Could not build because the file hasn\'t been saved');
					showResultsPanel();
					return;
				}

				var cwd = Path.directory(hxmlPath);
				hxmlContent = '--cwd "$cwd"\n' + sys.io.File.getContent(hxmlPath);

			case 'Packages/Haxe Minimal/syntax/haxe.tmLanguage':
				hxmlContent = HaxeProject.getHxmlForView(view);
				// can we use --run ?
		}

		if (hxmlContent == null) {
			// could not build because the file hasn't been saved
			appendPanel('A hxml file to build this file could not be found');
			showResultsPanel();
			return;
		}

		appendPanel('Build in progress\n');

		// @! The build command should not be using haxe server in --wait stdio mode because it means we only get compile output at the end
		// @! This is a big issue for C++ builds 
		// @! Should use server in normal mode to display messages as they are generated (we don't need tempfiles because build triggers save)
		var haxeServer = HaxeProject.getHaxeServerHandle(view, Stdio);
		buildHandle = haxeServer.buildAsync(
			hxmlContent,
			function(result){
				
				if (!result.hasError) {
					appendPanel('\nBuild complete\n');
					showResultsPanel();
				} else {
					appendPanel('\nBuild failed\n');
					showResultsPanel();
				}

				if (result.output.length > 0) {
					appendPanel('\n');
					appendPanel(result.output);
					showResultsPanel();
				}

				buildHandle = null;
			},
			function(log){
				appendPanel(log);
				showResultsPanel();
			}
		);
	}

	override function description(?args:python.Dict<String, Any>):String {
		if (args != null && args.get('kill') == true) {
			return "Cancels haxe compilation if in progress";
		}
		return "Compiles haxe code";
	}

	function clearBuildStatus(view: sublime.View) {
		view.erase_status('haxe_build_status');
	}

	function setBuildStatus(view: sublime.View, text: String) {
		view.set_status('haxe_build_status', text);
	}

	function clearResultsPanel() {
		panelLock.acquire();
		{
			// creating the panel implicitly clears any previous contents
			panel = window.create_output_panel('exec');
			var args = new python.Dict<String, Any>();
			panel.run_command('append', args);
		}
		panelLock.release();
	}

	function appendPanel(text: String) {
		panelLock.acquire();
		{
			// creating the panel implicitly clears any previous contents
			if (panel == null) {
				panel = window.create_output_panel('exec');
			}
			var args = new python.Dict<String, Any>();
			args.set('characters', text);
			panel.run_command('append', args);
		}
		panelLock.release();
	}

	function showResultsPanel() {
		panelLock.acquire();
		{
			// show build results
			var args = new python.Dict<String, Any>();
			args.set('panel', 'output.exec');
			window.run_command('show_panel', args);
		}
		panelLock.release();
	}

	function hideResultsPanel() {
		panelLock.acquire();
		{
			// show build results
			var args = new python.Dict<String, Any>();
			args.set('panel', 'output.exec');
			window.run_command('hide_panel', args);
		}
		panelLock.release();	
	}

}