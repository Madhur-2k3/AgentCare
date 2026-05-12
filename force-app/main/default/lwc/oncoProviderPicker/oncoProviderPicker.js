import { LightningElement, api, track } from 'lwc';

export default class OncoProviderPicker extends LightningElement {

    @api value;
    /** Provided by the Agentforce / Messaging for Web runtime */
    @api configuration;

    @track selectedResource = null;

    /**
     * Parse the raw providersList string into structured objects.
     * Each provider block looks like:
     *   1. Dr. Ananya Rao — Medical Oncology
     *      Facility: Onco Global Banjara Hills
     *      City: Hyderabad
     *      Address: Road No. 12, Banjara Hills, Hyderabad - 500034
     *      Title: Senior Medical Oncologist
     *      Schedule: Mon-Sat 9AM-5PM
     *      Resource: SR_Ananya_Rao
     *      Territory ID: 0HhXXXXXXXXXXXXXX
     */
    get providers() {
        if (!this.value || !this.value.providersList) {
            return [];
        }

        const raw = this.value.providersList;

        // Check if it's a "no results" message
        if (raw.startsWith('No providers')) {
            this._emptyMessage = raw;
            return [];
        }
        this._emptyMessage = '';

        // Split on the numbered pattern (e.g. "1. ", "2. ")
        const blocks = raw.split(/(?=\d+\.\s)/).filter(b => b.trim());

        return blocks.map(block => {
            const lines = block.split('\n').map(l => l.trim()).filter(l => l);

            // First line: "1. Dr. Ananya Rao — Medical Oncology"
            const firstLine = lines[0] ? lines[0].replace(/^\d+\.\s*/, '') : 'Unknown Provider';

            // Parse doctor name and specialty from first line
            let name = firstLine;
            let specialty = '';

            if (firstLine.includes(' — ')) {
                const parts = firstLine.split(' — ');
                name = parts[0].trim();
                specialty = (parts[1] || '').trim();
            }

            // Parse remaining key: value lines
            let facility = '';
            let city = '';
            let address = '';
            let title = '';
            let schedule = '';
            let resource = '';
            let territoryId = '';

            lines.forEach((line, idx) => {
                if (idx === 0) return;
                if (line.startsWith('Facility:')) {
                    facility = line.replace('Facility:', '').trim();
                } else if (line.startsWith('City:')) {
                    city = line.replace('City:', '').trim();
                } else if (line.startsWith('Address:')) {
                    address = line.replace('Address:', '').trim();
                } else if (line.startsWith('Title:')) {
                    title = line.replace('Title:', '').trim();
                } else if (line.startsWith('Schedule:')) {
                    schedule = line.replace('Schedule:', '').trim();
                } else if (line.startsWith('Resource:')) {
                    resource = line.replace('Resource:', '').trim();
                } else if (line.startsWith('Territory ID:')) {
                    territoryId = line.replace('Territory ID:', '').trim();
                }
            });

            const isSelected = resource === this.selectedResource;
            const cardClass = 'provider-card' + (isSelected ? ' provider-card-selected' : '');

            // Build initials from doctor name (e.g. "Dr. Ananya Rao" -> "AR")
            const cleanName = name.replace(/^Dr\.\s*/, '');
            const nameParts = cleanName.split(' ').filter(p => p);
            const initials = nameParts.length >= 2
                ? (nameParts[0][0] + nameParts[nameParts.length - 1][0]).toUpperCase()
                : cleanName.substring(0, 2).toUpperCase();

            return {
                name, specialty, facility, city, address,
                title, schedule, resource, territoryId,
                isSelected, cardClass, initials
            };
        });
    }

    get totalProviders() {
        return this.value ? this.value.totalProviders : 0;
    }

    get hasProviders() {
        return this.providers.length > 0;
    }

    get availableSpecialties() {
        if (!this.value || !this.value.availableSpecialties) return '';
        return this.value.availableSpecialties;
    }

    get hasSpecialties() {
        return this.availableSpecialties.length > 0;
    }

    get specialtyPills() {
        if (!this.availableSpecialties) return [];
        return this.availableSpecialties.split(',').map(s => s.trim()).filter(s => s);
    }

    get emptyMessage() {
        return this._emptyMessage || 'No providers found matching your criteria.';
    }

    get isEmptyResult() {
        return !this.hasProviders;
    }

    /**
     * Handle provider card click — send the selection back to the
     * Agentforce conversation as a user utterance.
     */
    handleProviderClick(event) {
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
                        console.log('Provider selection sent to agent:', doctorName, result);
                    })
                    .catch((error) => {
                        console.error('Failed to send provider selection:', error);
                    });
            } else {
                console.warn('No send method found on configuration.util');
            }
        } else {
            // Fallback: dispatch a bubbling custom event
            this.dispatchEvent(new CustomEvent('providerselected', {
                detail: {
                    resource: resource,
                    doctorName: doctorName,
                    utterance: utterance
                },
                bubbles: true,
                composed: true
            }));
            console.log('Dispatched providerselected event:', doctorName);
        }
    }

    connectedCallback() {
        console.log('ProviderPicker value:', JSON.stringify(this.value));
    }
}