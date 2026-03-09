export default class Component {
    constructor(options) {
        const {
            parent,
            storeKey,
            store,
            prop,
            inputType,
            values,
            locked,
            elementOptions = {}
        } = options || {};

        this.parent = parent;
        this.storeKey = storeKey;
        this.store = store;
        this.prop = prop;
        this.name = prop ? `${prop}`.toLowerCase() : '';

        this.inputType = inputType;
        this.values = values;
        this.locked = locked;
        this.options = elementOptions;

        this.debounceTime = 50;

        this.targetElement = parent?.element || false;
        this.elementTag = 'div';
        this.elementProps = {
            className: 'item'
        };
    }

    get dataType() {
        return Array.isArray(this.value) ? 'array' : typeof this.value;
    }

    get dataTypeValues() {
        return Array.isArray(this.values) ? 'array' : typeof this.values;
    }

    init() {
        Object.assign(this.elementProps, this.options);
    }

    render() {
        this.element = document.createElement(this.elementTag);
        Object.keys(this.elementProps).forEach(prop =>
            prop !== 'dataset' ? this.element[prop] = this.elementProps[prop] : null
        );
        this.elementProps.dataset
            ? Object.keys(this.elementProps.dataset).forEach(
                dataKey => this.element.dataset[dataKey] = this.elementProps.dataset[dataKey]
              )
            : null;
    }

    on(event, callback) {
        return this.parent?.events?.on(event, callback);
    }

    emit(event, ...args) {
        return this.parent?.events?.emit(event, ...args);
    }

    setValue(value) {
        this.element.value = value;
    }

    get value() {
        return this.store?.[this.prop];
    }

    set value(value) {
        clearTimeout(this.timer);
        this.timer = setTimeout(() => {
            if (this.store) this.store[this.prop] = value;
        }, this.debounceTime);
    }
}
