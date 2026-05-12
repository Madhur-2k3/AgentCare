import { LightningElement, api, track } from 'lwc';

export default class OncoDoctorPicker extends LightningElement {

    @api value;
    /** Provided by the Agentforce / Messaging for Web runtime */
    @api configuration;

    @track selectedResource = null;

    /**
     * Parse the raw doctorsList string into structured objects.
     * Each doctor block looks like:
     *   1. Dr. Ravi Sharma — Medical Oncology ✓ (Specialty Match)
     *      Senior Medical Oncologist, Onco Global
     *      Schedule: Mon-Sat 9AM-5PM
     *      Resource: SR_Ravi_Sharma
     */
    get doctors() {
        if (!this.value || !this.value.doctorsList) {
            return [];
        }

        const raw = this.value.doctorsList;

        // Check for the "Note:" prefix and extract it
        let noteText = '';
        let listContent = raw;
        if (raw.startsWith('Note:')) {
            const noteEnd = raw.indexOf('\n\n');
            if (noteEnd > -1) {
                noteText = raw.substring(0, noteEnd).trim();
                listContent = raw.substring(noteEnd + 2);
            }
        }
        this._noteText = noteText;

        // Split on the numbered pattern (e.g. "1. ", "2. ")
        const blocks = listContent.split(/(?=\d+\.\s)/).filter(b => b.trim());

        return blocks.map(block => {
            const lines = block.split('\n').map(l => l.trim()).filter(l => l);

            // First line: "1. Dr. Ravi Sharma — Medical Oncology ✓ (Specialty Match)"
            const firstLine = lines[0] ? lines[0].replace(/^\d+\.\s*/, '') : 'Unknown Doctor';

            // Parse doctor name and specialty from first line
            let name = firstLine;
            let specialty = '';
            let isSpecialtyMatch = false;

            if (firstLine.includes(' — ')) {
                const parts = firstLine.split(' — ');
                name = parts[0].trim();
                let specPart = parts[1] || '';
                if (specPart.includes('✓')) {
                    isSpecialtyMatch = true;
                    specPart = specPart.replace('✓', '').replace('(Specialty Match)', '').trim();
                }
                specialty = specPart;
            }

            // Remaining lines are key: value pairs
            let title = '';
            let schedule = '';
            let resource = '';

            lines.forEach((line, idx) => {
                if (idx === 0) return; // skip first line
                if (line.startsWith('Schedule:')) {
                    schedule = line.replace('Schedule:', '').trim();
                } else if (line.startsWith('Resource:')) {
                    resource = line.replace('Resource:', '').trim();
                } else if (!line.startsWith('Schedule:') && !line.startsWith('Resource:') && idx === 1) {
                    // Title line (e.g. "Senior Medical Oncologist, Onco Global")
                    title = line;
                }
            });

            const isSelected = resource === this.selectedResource;
            const cardClass = 'doctor-card' + (isSelected ? ' doctor-card-selected' : '');
            const matchBadgeClass = isSpecialtyMatch ? 'match-badge' : 'slds-hide';

            return { name, specialty, title, schedule, resource, isSpecialtyMatch, isSelected, cardClass, matchBadgeClass };
        });
    }

    get totalDoctors() {
        return this.value ? this.value.totalDoctors : 0;
    }

    get hasDoctors() {
        return this.doctors.length > 0;
    }

    get hasNote() {
        return this._noteText && this._noteText.length > 0;
    }

    get noteText() {
        return this._noteText || '';
    }

    /**
     * Handle doctor card click — send the selection back to the
     * Agentforce conversation as a user utterance.
     */
    handleDoctorClick(event) {
        const resource = event.currentTarget.dataset.resource;
        const doctorName = event.currentTarget.dataset.name;

        // Visual feedback
        this.selectedResource = resource;

        // Build a natural-language utterance for the agent
        const utterance = `I want to book with ${doctorName}`;

        // Primary approach: use the Messaging for Web / Agentforce utility
        if (this.configuration && this.configuration.util) {
            const util = this.configuration.util;
            const sendFn = util.sendTextMessage || util.sendMessage;
            if (sendFn) {
                sendFn.call(util, utterance)
                    .then((result) => {
                        console.log('Doctor selection sent to agent:', doctorName, result);
                    })
                    .catch((error) => {
                        console.error('Failed to send doctor selection:', error);
                    });
            } else {
                console.warn('No send method found on configuration.util');
            }
        } else {
            // Fallback: dispatch a bubbling custom event
            this.dispatchEvent(new CustomEvent('doctorselected', {
                detail: {
                    resource: resource,
                    doctorName: doctorName,
                    utterance: utterance
                },
                bubbles: true,
                composed: true
            }));
            console.log('Dispatched doctorselected event:', doctorName);
        }
    }

    connectedCallback() {
        console.log('DoctorPicker value:', JSON.stringify(this.value));
    }
}