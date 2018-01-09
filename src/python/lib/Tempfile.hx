package python.lib;

@:pythonImport("tempfile")
extern class Tempfile {

	public static function TemporaryFile(?mode: String, ?buffering: Int, ?encoding: String, ?newline: String, ?suffix: String, ?prefix: String, ?dir: String): python.lib.io.FileIO;
	public static function NamedTemporaryFile(?mode: String, ?buffering: Int, ?encoding: String, ?newline: String, ?suffix: String, ?prefix: String, ?dir: String, ?delete: Bool): python.lib.io.FileIO;
	public static function gettempdir():String;
	public static function mkstemp(?suffix: String, ?prefix: String, ?dir: String, ?textMode: Bool): python.Tuple.Tuple2<python.lib.FileDescriptor, String>;

}