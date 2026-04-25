import { LightningElement, api, track } from 'lwc';
import getSlotsForDate from '@salesforce/apex/OncoGetAvailableSlots.getSlotsForDate';

export default class OncoSlotPicker extends LightningElement {

    @api value;
    @api configuration;

    @track selectedSlotKey = null;
    @track selectedDateIndex = 0;
    @track dateSlots = [];        // slots for the currently selected date
    @track isLoading = false;
    @track dateInfoMessage = '';
    @track currentTotalSlots = 0;

    _datesInitialized = false;

    connectedCallback() {
        console.log('SlotPicker value:', JSON.stringify(this.value));
        // Initialize with the data from the agent response
        if (this.value && this.value.availableSlots) {
            this.dateSlots = this._parseSlotsString(this.value.availableSlots);
            this.currentTotalSlots = this.value.totalSlots || 0;
            if (this.dateSlots.length === 0 && this.value.availableSlots) {
                this.dateInfoMessage = this.value.availableSlots.match(/^\d+\./) ? '' : this.value.availableSlots;
            }
        }
        // Find which date index matches the initial data
        this._initSelectedDate();
    }

    // ── Date Carousel ──────────────────────────────────────────────

    /** Generate 7 days starting from today */
    get calendarDates() {
        const dates = [];
        const today = new Date();
        const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

        for (let i = 0; i < 7; i++) {
            const d = new Date(today);
            d.setDate(today.getDate() + i);

            const dayName = dayNames[d.getDay()];
            const dayNum = d.getDate();
            const month = d.getMonth() + 1;
            const year = d.getFullYear();
            // Format as YYYY-MM-DD for Apex
            const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`;
            // Display format matching Apex output (M/d/yyyy)
            const displayDate = `${month}/${dayNum}/${year}`;

            const isSelected = i === this.selectedDateIndex;
            const isToday = i === 0;
            const chipClass = 'date-chip' + (isSelected ? ' date-chip-selected' : '');

            dates.push({
                key: dateStr,
                dayName,
                dayNum,
                dateStr,
                displayDate,
                isSelected,
                isToday,
                chipClass,
                index: i
            });
        }
        return dates;
    }

    _initSelectedDate() {
        if (!this.value || !this.value.availableSlots) return;
        // Try to match the date from initial slots
        const slots = this.dateSlots;
        if (slots.length > 0) {
            const firstDate = slots[0].date; // e.g. "4/28/2026"
            const dates = this.calendarDates;
            for (let i = 0; i < dates.length; i++) {
                if (dates[i].displayDate === firstDate) {
                    this.selectedDateIndex = i;
                    return;
                }
            }
        }
    }

    // ── Doctor Info ─────────────────────────────────────────────────

    get doctorName() {
        return this.value ? this.value.doctorName : '';
    }

    get hasDoctorName() {
        return this.doctorName && this.doctorName.length > 0;
    }

    get workTypeName() {
        return this.value ? this.value.workTypeName : '';
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

    // ── Slot Display ────────────────────────────────────────────────

    get hasSlots() {
        return this.dateSlots.length > 0;
    }

    get hasDateInfoMessage() {
        return this.dateInfoMessage && this.dateInfoMessage.length > 0;
    }

    /** Group slots by Morning / Afternoon */
    get slotGroups() {
        const groups = {};
        this.dateSlots.forEach(slot => {
            if (!groups[slot.period]) {
                groups[slot.period] = { period: slot.period, icon: slot.periodIcon, slots: [], key: slot.period };
            }
            groups[slot.period].slots.push(slot);
        });
        return Object.values(groups);
    }

    get hasSlotGroups() {
        return this.slotGroups.length > 0;
    }

    get showContent() {
        return this.value !== null && this.value !== undefined;
    }

    // ── Date Navigation ─────────────────────────────────────────────

    get canGoPrev() {
        return this.selectedDateIndex > 0;
    }

    get canGoNext() {
        return this.selectedDateIndex < 6;
    }

    get prevBtnClass() {
        return 'nav-btn' + (this.canGoPrev ? '' : ' nav-btn-disabled');
    }

    get nextBtnClass() {
        return 'nav-btn' + (this.canGoNext ? '' : ' nav-btn-disabled');
    }

    handlePrevDate() {
        if (this.canGoPrev) {
            this.selectedDateIndex--;
            this._fetchSlotsForSelectedDate();
        }
    }

    handleNextDate() {
        if (this.canGoNext) {
            this.selectedDateIndex++;
            this._fetchSlotsForSelectedDate();
        }
    }

    handleDateClick(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx !== this.selectedDateIndex) {
            this.selectedDateIndex = idx;
            this._fetchSlotsForSelectedDate();
        }
    }

    // ── Fetch Slots via Imperative Apex ─────────────────────────────

    _fetchSlotsForSelectedDate() {
        if (!this.value) return;

        const selectedDate = this.calendarDates[this.selectedDateIndex];
        this.isLoading = true;
        this.dateInfoMessage = '';
        this.selectedSlotKey = null;

        getSlotsForDate({
            serviceResourceName: this.value.serviceResourceName,
            serviceTerritoryId: this.value.serviceTerritoryId,
            workTypeName: this.value.workTypeName,
            dateStr: selectedDate.dateStr
        })
            .then(result => {
                const slotsStr = result.availableSlots || '';
                this.currentTotalSlots = result.totalSlots || 0;
                this.dateSlots = this._parseSlotsString(slotsStr);
                if (this.dateSlots.length === 0) {
                    this.dateInfoMessage = slotsStr.match(/^\d+\./) ? '' : slotsStr;
                }
            })
            .catch(error => {
                console.error('Error fetching slots:', error);
                this.dateInfoMessage = 'Unable to load slots. Please try again.';
                this.dateSlots = [];
                this.currentTotalSlots = 0;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ── Slot Click → Send to Agent ──────────────────────────────────

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

    // ── Parse Helper ────────────────────────────────────────────────

    _parseSlotsString(raw) {
        if (!raw || !raw.match(/^\d+\./)) return [];

        const blocks = raw.split('\n').filter(b => b.trim());
        return blocks.map(line => {
            const cleaned = line.replace(/^\d+\.\s*/, '');
            let date = '', startTime = '', endTime = '', duration = '';

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

            const isAM = startTime.toUpperCase().includes('AM');
            const period = isAM ? 'Morning' : 'Afternoon';
            const periodIcon = isAM ? '🌅' : '☀️';
            const key = `${date}-${startTime}`;
            const isSelected = key === this.selectedSlotKey;
            const pillClass = 'slot-pill' + (isSelected ? ' slot-pill-selected' : '');

            return { key, date, startTime, endTime, duration, period, periodIcon, isSelected, pillClass };
        });
    }
}
