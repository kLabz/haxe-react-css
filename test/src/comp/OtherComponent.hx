package comp;

@:css(OtherComponent.css)
class OtherComponent extends ReactComponent {
	override function render():ReactFragment {
		return <div className={className}>Other component</div>;
	}
}
