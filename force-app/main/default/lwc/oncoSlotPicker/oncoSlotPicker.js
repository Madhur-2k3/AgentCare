import { LightningElement, api, track } from 'lwc';

export default class OncoSlotPicker extends LightningElement {

    @api value;
    @api configuration;

    @track selectedSlotKey = null;

    /**
     * Parse the raw availableSlots string into structured slot objects.
     * Format: "1. 4/28/2026 — 9:00 AM to 9:30 AM (30 min)\n"
     */
    get slots() {
        if (!this.value || !this.value.availableSlots) return [];

        const raw = this.value.availableSlots;

        // If it's an error/info message (no numbered list), return empty
        if (!raw.match(/^\d+\./)) return [];

        const blocks = raw.split('\n').filter(b => b.trim());

        return blocks.map(line => {
            const cleaned = line.replace(/^\d+\.\s*/, '');

            // Parse: "4/28/2026 — 9:00 AM to 9:30 AM (30 min)"
            let date = '';
            let startTime = '';
            let endTime = '';
            let duration = '';

            const dashSplit = cleaned.split(' — ');
            if (dashSplit.length === 2) {
                date = dashSplit[0].trim();
                const timePart = dashSplit[1];

                const timeMatch = timePart.match(/(.+?)\s+to\s+(.+?)\s+\((\d+)\s*min\)/);
                if (timeMatch) {
                    startTime = timeMatch[1].trim();
                    endTime = timeMatch[2].trim();
                    duration = timeMatch[3];
                }
            }

            // Determine AM/PM period for grouping
            const isAM = startTime.toUpperCase().includes('AM');
            const period = isAM ? 'Morning' : 'Afternoon';
            const periodIcon = isAM ? '🌅' : '☀️';

            const key = `${date}-${startTime}`;
            const isSelected = key === this.selectedSlotKey;
            const pillClass = 'slot-pill' + (isSelected ? ' slot-pill-selected' : '');

            return { key, date, startTime, endTime, duration, period, periodIcon, isSelected, pillClass };
        });
    }

    /** Group slots by period (Morning / Afternoon) */
    get slotGroups() {
        const slots = this.slots;
        const groups = {};
        slots.forEach(slot => {
            if (!groups[slot.period]) {
                groups[slot.period] = { period: slot.period, icon: slot.periodIcon, slots: [] };
            }
            groups[slot.period].slots.push(slot);
        });
        return Object.values(groups);
    }

    get hasSlotGroups() {
        return this.slotGroups.length > 0;
    }

    get totalSlots() {
        return this.value ? this.value.totalSlots : 0;
    }

    get hasSlots() {
        return this.totalSlots > 0;
    }

    get durationMinutes() {
        return this.value ? this.value.durationMinutes : 0;
    }

    get prepInstructions() {
        return this.value ? this.value.prepInstructions : '';
    }

    get hasPrepInstructions() {
        return this.prepInstructions && this.prepInstructions.length > 0;
    }

    /** For the date display header */
    get appointmentDate() {
        const slots = this.slots;
        return slots.length > 0 ? slots[0].date : '';
    }

    /** Error/info message when no slots exist */
    get infoMessage() {
        if (!this.value || !this.value.availableSlots) return '';
        const raw = this.value.availableSlots;
        if (!raw.match(/^\d+\./)) return raw;
        return '';
    }

    get hasInfoMessage() {
        return this.infoMessage.length > 0;
    }

    handleSlotClick(event) {
        const key = event.currentTarget.dataset.key;
        const startTime = event.currentTarget.dataset.start;
        const endTime = event.currentTarget.dataset.end;
        const date = event.currentTarget.dataset.date;

        this.selectedSlotKey = key;

        const utterance = `I want the ${startTime} to ${endTime} slot on ${date}`;

        if (this.configuration && this.configuration.util) {
            const util = this.configuration.util;
            const sendFn = util.sendTextMessage || util.sendMessage;
            if (sendFn) {
                sendFn.call(util, utterance)
                    .then(() => console.log('Slot selection sent:', startTime))
                    .catch((err) => console.error('Send failed:', err));
            }
        } else {
            this.dispatchEvent(new CustomEvent('slotselected', {
                detail: { date, startTime, endTime, utterance },
                bubbles: true,
                composed: true
            }));
        }
    }

    connectedCallback() {
        console.log('SlotPicker value:', JSON.stringify(this.value));
    }
}
