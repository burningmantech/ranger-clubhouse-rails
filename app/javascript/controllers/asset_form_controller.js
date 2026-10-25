import { Controller } from "@hotwired/stimulus";

const RADIO_LABELS = {
    radio: {
        false: "Shift",
        true: "Event",
    },
    default: {
        false: "Temporary",
        true: "Permanent",
    },
};

export default class extends Controller {
    static targets = ["typeSelect", "durationGroup"];

    connect() {
        this.updateDurationLabels();
    }

    handleTypeChange() {
        this.updateDurationLabels();
    }

    updateDurationLabels() {
        if (!this.hasTypeSelectTarget || !this.hasDurationGroupTarget) {
            return;
        }

        const labels = this.typeSelectTarget.value === "radio" ? RADIO_LABELS.radio : RADIO_LABELS.default;

        this.updateOptionLabel("false", labels.false);
        this.updateOptionLabel("true", labels.true);
    }

    updateOptionLabel(value, text) {
        const label = this.durationGroupTarget.querySelector(`label[for$="_${value}"]`);

        if (label) {
            label.textContent = text;
        }
    }
}
