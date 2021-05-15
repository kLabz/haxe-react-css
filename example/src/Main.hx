import js.Browser;
import js.html.DivElement;
import react.ReactDOM;
import react.ReactMacro.jsx;

import comp.OtherComponent;
import comp.TestComponent;

class Main {
	public static var root(get, null):DivElement;

	static function get_root():DivElement {
		if (root == null) root = cast Browser.document.querySelector('#app');
		return root;
	}

	public static function main() {
		ReactDOM.render(jsx(<>
			Test root
			<OtherComponent />
			<TestComponent />
			<TestComponent />
			<OtherComponent />
		</>), root);
	}
}
