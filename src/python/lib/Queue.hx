package python.lib;

@:pythonImport("queue", "Queue")
extern class Queue {

	public function new() {}

	public function put(item: Any, ?block: Bool, ?timeout: Float): Void;
	public function get(?block: Bool, ?timeout: Float): Any;

}

@:pythonImport("queue", "Empty")
extern class Empty {}