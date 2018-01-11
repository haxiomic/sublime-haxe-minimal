from .haxe_minimal import HaxePlugin

# Forward module level plugin_unloaded call
def plugin_unloaded():
	HaxePlugin.plugin_unloaded()