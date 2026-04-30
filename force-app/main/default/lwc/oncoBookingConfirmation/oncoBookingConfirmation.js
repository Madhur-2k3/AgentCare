import { LightningElement, api } from 'lwc';

export default class OncoBookingConfirmation extends LightningElement {

    @api value;
    @api configuration;

    /**
     * Parse the confirmationMessage into structured fields.
     * Format:
     *   Appointment Booked Successfully!
     *
     *   Patient: Karthik Gowda
     *   Doctor: Dr. Arjun Nair
     *   Type: Palliative Care Consultation
     *   Facility: Onco Global Whitefield Cancer Center
     *   Address: ITPL Main Road, Whitefield, Bengaluru - 560066
     *   Date & Time: Monday, April 27, 2026 at 11:30 PM
     *   Duration: 40 minutes
     *   Appointment ID: 08pbm000000KT97AAG
     *
     *   Preparation: Supportive care assessment...
     *
     *   Please arrive 15 minutes before your scheduled time.
     */
    get booking() {
        if (!this.value || !this.value.confirmationMessage) return null;

        const raw = this.value.confirmationMessage;
        const lines = raw.split('\n');

        const data = {
            title: '',
            patient: '',
            doctor: '',
            type: '',
            facility: '',
            address: '',
            dateTime: '',
            duration: '',
            appointmentId: '',
            preparation: '',
            arrivalNote: ''
        };

        lines.forEach(line => {
            const trimmed = line.trim();
            if (trimmed.startsWith('Patient:')) data.patient = trimmed.replace('Patient:', '').trim();
            else if (trimmed.startsWith('Doctor:')) data.doctor = trimmed.replace('Doctor:', '').trim();
            else if (trimmed.startsWith('Type:')) data.type = trimmed.replace('Type:', '').trim();
            else if (trimmed.startsWith('Facility:')) data.facility = trimmed.replace('Facility:', '').trim();
            else if (trimmed.startsWith('Address:')) data.address = trimmed.replace('Address:', '').trim();
            else if (trimmed.startsWith('Date & Time:')) data.dateTime = trimmed.replace('Date & Time:', '').trim();
            else if (trimmed.startsWith('Duration:')) data.duration = trimmed.replace('Duration:', '').trim();
            else if (trimmed.startsWith('Appointment ID:')) data.appointmentId = trimmed.replace('Appointment ID:', '').trim();
            else if (trimmed.startsWith('Preparation:')) data.preparation = trimmed.replace('Preparation:', '').trim();
            else if (trimmed.includes('arrive') && trimmed.includes('minutes')) data.arrivalNote = trimmed;
            else if (trimmed.includes('Booked Successfully') || trimmed.includes('Booking failed')) data.title = trimmed;
        });

        return data;
    }

    get isSuccess() {
        return this.value && this.value.success === true;
    }

    get isFailure() {
        return this.value && this.value.success === false;
    }

    get hasBooking() {
        return this.booking !== null && this.booking.title.length > 0;
    }

    get hasPreparation() {
        return this.booking && this.booking.preparation && this.booking.preparation.length > 0;
    }

    get hasArrivalNote() {
        return this.booking && this.booking.arrivalNote && this.booking.arrivalNote.length > 0;
    }

    get statusIcon() {
        return this.isSuccess ? 'action:approval' : 'action:close';
    }

    get errorMessage() {
        if (!this.value || !this.value.confirmationMessage) return '';
        return this.value.confirmationMessage;
    }

    get receiptUrl() {
        if (!this.booking || !this.booking.appointmentId) return '#';
        // Use the community base path so it works on Experience Cloud sites
        // On a site like orgfarm-xxx.my.site.com/OncoGlobalPatientPortal1/s/
        // the VF page is accessible at /OncoGlobalPatientPortal1/apex/OncoBookingReceipt
        const basePath = window.location.pathname.split('/s/')[0] || '';
        return basePath + '/apex/OncoBookingReceipt?id=' + this.booking.appointmentId;
    }

    connectedCallback() {
        console.log('BookingConfirmation value:', JSON.stringify(this.value));
    }
}
