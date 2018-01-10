// Imports should not be removed – Sublime Text uses the imported class code
import HaxeView;
import HaxeBuildCommand;

class HaxePlugin {

	static public inline var id = 'haxe_minimal';

	// may throw if the process fails to start
	static var haxeServerHandle: HaxeServer = null;
	static public function getHaxeServerHandle(view: sublime.View) {
		if (haxeServerHandle == null) {
			haxeServerHandle = new HaxeServer();
		}

		return haxeServerHandle;
	}

	static function main() {
		// replace haxe.Log.trace so it only uses print()
		// this is because sublime text has only partial stdout/stderr objects
		haxe.Log.trace = function(v, ?infos) {
			var str: String = Std.string(v);
			var prefix = '';
			var suffix = '';
			if (infos != null) {
				prefix = '${infos.fileName}:${infos.lineNumber}: ';
				suffix = infos.customParams != null ? (', ' + infos.customParams.join(', ')) : '';
			}
			untyped print(prefix + str + suffix);
		}
	}

}