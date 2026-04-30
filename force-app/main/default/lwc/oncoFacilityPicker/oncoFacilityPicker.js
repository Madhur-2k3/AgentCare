import { LightningElement, api, track } from 'lwc';

export default class OncoFacilityPicker extends LightningElement {

    @api value;
    /** Provided by the Agentforce / Messaging for Web runtime */
    @api configuration;

    @track selectedTerritoryId = null;

    /**
     * Parse the raw facilitiesList string into structured objects.
     * Each facility block looks like:
     *   1. Onco Global Indiranagar Oncology Institute
     *      Address: 100 Feet Road, Indiranagar, Bengaluru - 560038
     *      Hours: Operating hours for …
     *      Territory ID: 0Hhbm000000SoBcCAK
     */
    get facilities() {
        if (!this.value || !this.value.facilitiesList) {
            return [];
        }

        const raw = this.value.facilitiesList;
        // Split on the numbered pattern (e.g. "1. ", "2. ")
        const blocks = raw.split(/(?=\d+\.\s)/).filter(b => b.trim());

        return blocks.map(block => {
            const lines = block.split('\n').map(l => l.trim()).filter(l => l);

            // First line: "1. Facility Name"
            const name = lines[0] ? lines[0].replace(/^\d+\.\s*/, '') : 'Unknown Facility';

            // Remaining lines are key: value pairs
            let address = '';
            let hours = '';
            let territoryId = '';

            lines.forEach(line => {
                if (line.startsWith('Address:')) {
                    address = line.replace('Address:', '').trim();
                } else if (line.startsWith('Hours:')) {
                    hours = line.replace('Hours:', '').trim();
                } else if (line.startsWith('Territory ID:')) {
                    territoryId = line.replace('Territory ID:', '').trim();
                }
            });

            const isSelected = territoryId === this.selectedTerritoryId;
            const cardClass = 'facility-card' + (isSelected ? ' facility-card-selected' : '');

            return { name, address, hours, territoryId, isSelected, cardClass };
        });
    }

    get totalFacilities() {
        return this.value ? this.value.totalFacilities : 0;
    }

    get hasFacilities() {
        return this.facilities.length > 0;
    }

    /**
     * Handle facility card click — send the selection back to the
     * Agentforce conversation as a user utterance.
     */
    handleFacilityClick(event) {
        const territoryId = event.currentTarget.dataset.territoryid;
        const facilityName = event.currentTarget.dataset.name;

        // Visual feedback
        this.selectedTerritoryId = territoryId;

        // Build a natural-language utterance for the agent
        const utterance = `I want to book at ${facilityName}`;

        if (this.configuration && this.configuration.util) {
            const util = this.configuration.util;

            // Log available methods to discover the correct API
            console.log('util methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(util)));
            console.log('util own keys:', Object.keys(util));
            console.log('sendTextMessage?', typeof util.sendTextMessage);
            console.log('sendMessage?', typeof util.sendMessage);

            // Try sendTextMessage first, fallback to sendMessage
            const sendFn = util.sendTextMessage || util.sendMessage;
            if (sendFn) {
                sendFn.call(util, utterance)
                    .then((result) => {
                        console.log('Message sent! Result:', result);
                    })
                    .catch((error) => {
                        console.error('Send failed:', error);
                    });
            } else {
                console.warn('No send method found on util. Available:', Object.getOwnPropertyNames(util));
            }
        } else {
            // Fallback: dispatch a bubbling custom event for the parent container
            this.dispatchEvent(new CustomEvent('facilityselected', {
                detail: {
                    territoryId: territoryId,
                    facilityName: facilityName,
                    utterance: utterance
                },
                bubbles: true,
                composed: true
            }));
            console.log('Dispatched facilityselected event (configuration.util not available):', facilityName);
        }
    }

    connectedCallback() {
        console.log('FacilityPicker value:', JSON.stringify(this.value));
        if (this.configuration && this.configuration.util) {
            const util = this.configuration.util;
            console.log('configuration.util available. Methods on prototype:',
                Object.getOwnPropertyNames(Object.getPrototypeOf(util)));
            console.log('Own keys on util:', Object.keys(util));
            console.log('typeof sendTextMessage:', typeof util.sendTextMessage);
            console.log('typeof sendMessage:', typeof util.sendMessage);
        } else {
            console.log('configuration or util is null/undefined:', this.configuration);
        }
    }
}