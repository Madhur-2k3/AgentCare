import { LightningElement, api } from 'lwc';

export default class OncoFacilityPicker extends LightningElement {

    @api value;

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

            return { name, address, hours, territoryId };
        });
    }

    get totalFacilities() {
        return this.value ? this.value.totalFacilities : 0;
    }

    get hasFacilities() {
        return this.facilities.length > 0;
    }

    connectedCallback() {
        console.log('FacilityPicker value:', JSON.stringify(this.value));
    }
}
