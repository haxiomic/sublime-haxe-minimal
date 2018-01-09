// Python OS methods missing from the haxe standard library
package python.lib;

@:pythonImport("os")
extern class OsExtended {

	public static function fdopen(fd:FileDescriptor, mode: String, ?buffSize: Int): python.lib.io.FileIO;

}