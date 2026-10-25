import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["progress"]
    static values = {
        autoHide: {type: Boolean, default: true},
        delay: {type: Number, default: 6000}
    }

    connect() {
        // Show toast by adding 'show' class
        this.element.classList.add('show');
        
        // Auto-hide if enabled
        if (this.autoHideValue) {
            this.startCountdown();
        }

        // Animate progress bar if present
        if (this.hasProgressTarget) {
            this.animateProgress();
        }
    }

    disconnect() {
        this.clearCountdown();
    }

    close() {
        this.destroyToast();
    }

    pause() {
        if (!this.autoHideValue) return;
        
        this.clearCountdown();
        
        // Pause progress bar animation
        if (this.hasProgressTarget) {
            const computedStyle = window.getComputedStyle(this.progressTarget);
            const currentWidth = computedStyle.width;
            this.progressTarget.style.width = currentWidth;
            this.progressTarget.style.transition = 'none';
        }
    }

    resume() {
        if (!this.autoHideValue) return;
        
        // Calculate remaining time based on progress bar width
        if (this.hasProgressTarget) {
            const currentWidth = parseFloat(window.getComputedStyle(this.progressTarget).width);
            const totalWidth = this.progressTarget.parentElement.offsetWidth;
            const remainingRatio = currentWidth / totalWidth;
            const remainingTime = this.delayValue * remainingRatio;
            
            // Resume countdown
            this.timeoutId = setTimeout(() => {
                this.destroyToast();
            }, remainingTime);
            
            // Resume progress bar animation
            this.progressTarget.style.transitionDuration = `${remainingTime}ms`;
            this.progressTarget.style.width = '0%';
        } else {
            this.startCountdown();
        }
    }

    startCountdown() {
        this.timeoutId = setTimeout(() => {
            this.destroyToast();
        }, this.delayValue);
    }

    clearCountdown() {
        if (this.timeoutId) {
            clearTimeout(this.timeoutId);
            this.timeoutId = null;
        }
    }

    animateProgress() {
        // Set transition duration to match delay
        this.progressTarget.style.transitionDuration = `${this.delayValue}ms`;
        
        // Trigger animation on next frame
        requestAnimationFrame(() => {
            this.progressTarget.style.width = '0%';
        });
    }

    destroyToast() {
        this.clearCountdown();
        
        // Remove show class and then remove element after transition
        this.element.classList.remove('show');
        setTimeout(() => {
            this.element.remove();
        }, 300); // Wait for CSS transition
    }
}
