import { LightningElement, api, track } from 'lwc';

export default class OncoAppointmentList extends LightningElement {

    @api value;
    @api configuration;

    @track selectedApptId = null;

    /**
     * Parse the raw appointmentsList string into structured appointment objects.
     * Each block:
     *   1. Follow-Up Review with Dr. Ananya Rao
     *      Status: Scheduled
     *      Date: Monday, April 28, 2026
     *      Time: 9:00 AM to 9:30 AM
     *      Facility: Onco Global Whitefield Cancer Center
     *      Address: ITPL Main Road, Whitefield, Bengaluru - 560066
     *      Appointment ID: 08pbm000000KT97AAG
     */
    get appointments() {
        if (!this.value || !this.value.appointmentsList) return [];
        const raw = this.value.appointmentsList;
        if (!raw.match(/^\d+\./)) return [];

        const blocks = raw.split(/(?=\d+\.\s)/).filter(b => b.trim());

        return blocks.map(block => {
            const lines = block.split('\n').map(l => l.trim()).filter(l => l);

            // First line: "1. Follow-Up Review with Dr. Ananya Rao"
            const firstLine = lines[0] ? lines[0].replace(/^\d+\.\s*/, '') : '';
            let type = firstLine;
            let doctor = '';
            if (firstLine.includes(' with ')) {
                const parts = firstLine.split(' with ');
                type = parts[0].trim();
                doctor = parts[1].trim();
            }

            let status = '', date = '', time = '', facility = '', address = '', apptId = '';

            lines.forEach((line, idx) => {
                if (idx === 0) return;
                if (line.startsWith('Status:')) status = line.replace('Status:', '').trim();
                else if (line.startsWith('Date:')) date = line.replace('Date:', '').trim();
                else if (line.startsWith('Time:')) time = line.replace('Time:', '').trim();
                else if (line.startsWith('Facility:')) facility = line.replace('Facility:', '').trim();
                else if (line.startsWith('Address:')) address = line.replace('Address:', '').trim();
                else if (line.startsWith('Appointment ID:')) apptId = line.replace('Appointment ID:', '').trim();
            });

            // Status styling
            const statusLower = status.toLowerCase();
            let statusClass = 'status-badge status-scheduled';
            let statusIcon = 'utility:clock';
            if (statusLower === 'completed') {
                statusClass = 'status-badge status-completed';
                statusIcon = 'utility:check';
            } else if (statusLower === 'canceled' || statusLower === 'cancelled') {
                statusClass = 'status-badge status-canceled';
                statusIcon = 'utility:close';
            }

            const isSelected = apptId === this.selectedApptId;
            const cardClass = 'appt-card' + (isSelected ? ' appt-card-selected' : '');
            const isScheduled = statusLower === 'scheduled';

            return {
                key: apptId || `appt-${Math.random()}`,
                type, doctor, status, date, time, facility, address, apptId,
                statusClass, statusIcon, cardClass, isSelected, isScheduled
            };
        });
    }

    get totalAppointments() {
        return this.value ? this.value.totalAppointments : 0;
    }

    get hasAppointments() {
        return this.appointments.length > 0;
    }

    get infoMessage() {
        if (!this.value || !this.value.appointmentsList) return '';
        const raw = this.value.appointmentsList;
        if (!raw.match(/^\d+\./)) return raw;
        return '';
    }

    get hasInfoMessage() {
        return this.infoMessage && this.infoMessage.length > 0;
    }

    handleApptClick(event) {
        const apptId = event.currentTarget.dataset.apptid;
        const type = event.currentTarget.dataset.type;
        const doctor = event.currentTarget.dataset.doctor;

        this.selectedApptId = apptId;

        const utterance = `I want to reschedule my ${type} appointment with ${doctor}, Appointment ID ${apptId}`;

        if (this.configuration && this.configuration.util) {
            const util = this.configuration.util;
            const sendFn = util.sendTextMessage || util.sendMessage;
            if (sendFn) {
                sendFn.call(util, utterance)
                    .then(() => console.log('Appointment selected:', apptId))
                    .catch((err) => console.error('Send failed:', err));
            }
        } else {
            this.dispatchEvent(new CustomEvent('appointmentselected', {
                detail: { apptId, type, doctor, utterance },
                bubbles: true,
                composed: true
            }));
        }
    }

    connectedCallback() {
        console.log('AppointmentList value:', JSON.stringify(this.value));
    }
}