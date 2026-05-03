/**
 * AppointmentEmailService
 * ─────────────────────────────────────────────────────────────────────────────
 * Invocable Apex class for Service Appointment email notifications.
 * Called from a Record-Triggered Flow on ServiceAppointment.
 *
 * Supports three contexts via the `emailType` input parameter:
 *   • CONFIRMATION  → immediate on creation
 *   • REMINDER_24H  → scheduled path, 24 hrs before SchedStartTime
 *   • REMINDER_12H  → scheduled path, 12 hrs before SchedStartTime
 *
 * Lookup traversal:
 *   ContactId  → doctor name, title, email (placed in CC)
 *   AccountId  → patient name, email (placed in To)
 * ─────────────────────────────────────────────────────────────────────────────
 */
public with sharing class AppointmentEmailService {

    // ─── Inner class used as Flow input ──────────────────────────────────────
    public class AppointmentEmailRequest {
        @InvocableVariable(label='Service Appointment Id' required=true)
        public Id serviceAppointmentId;

        /**
         * Allowed values: CONFIRMATION | REMINDER_24H | REMINDER_12H
         */
        @InvocableVariable(label='Email Type' required=true)
        public String emailType;
    }

    // ─── Invocable entry-point ────────────────────────────────────────────────
    @InvocableMethod(
        label       = 'Send Appointment Email'
        description = 'Sends confirmation or reminder emails for a Service Appointment. emailType: CONFIRMATION | REMINDER_24H | REMINDER_12H'
        category    = 'Service Appointment'
    )
    public static void sendAppointmentEmail(List<AppointmentEmailRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        // Collect unique appointment IDs and route by email type
        Map<Id, String> typeByApptId = new Map<Id, String>();

        for (AppointmentEmailRequest req : requests) {
            if (req.serviceAppointmentId != null && String.isNotBlank(req.emailType)) {
                typeByApptId.put(req.serviceAppointmentId, req.emailType);
            }
        }

        if (typeByApptId.isEmpty()) return;

        // ── Single SOQL to fetch all required fields ──────────────────────────
        List<ServiceAppointment> appointments = [
            SELECT
                Id,
                Subject,
                SchedStartTime,
                SchedEndTime,
                Street,
                City,
                State,
                PostalCode,
                Country,
                ApptBookingInfoUrl,
                AccountId,
                Account.Name,
                Account.PersonEmail,          
                Account.BillingStreet,
            	Account.PersonContactId,
                ContactId,
                Contact.Name,
                Contact.Title,
                Contact.Email
            FROM ServiceAppointment
            WHERE Id IN :typeByApptId.keySet()
        ];
		System.debug('SCHEDULE TIME:::::::::'+ appointments[0].SchedStartTime);
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (ServiceAppointment appt : appointments) {
            String emailType = typeByApptId.get(appt.Id);

            switch on emailType.toUpperCase() {
                when 'CONFIRMATION' {
                    emailsToSend.add(buildConfirmationEmail(appt));
                }
                when 'REMINDER_24H' {
                    emailsToSend.add(buildReminderEmail(appt, 24));
                }
                when 'REMINDER_12H' {
                    emailsToSend.add(buildReminderEmail(appt, 12));
                }
            }
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend, true);
        }
    }


    // ═════════════════════════════════════════════════════════════════════════
    //  EMAIL BUILDERS
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Builds the appointment confirmation email sent immediately on creation.
     */
    private static Messaging.SingleEmailMessage buildConfirmationEmail(ServiceAppointment appt) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		//mail.setSenderDisplayName('OncoGlobal India');
        mail.setToAddresses(resolvePatientEmails(appt));
        mail.setCcAddresses(resolveDoctorEmails(appt));
        mail.setSubject('✅ Appointment Confirmed – ' + formatDateTime(appt.SchedStartTime));
        mail.setHtmlBody(buildConfirmationHtml(appt));
        mail.setSaveAsActivity(true);
        mail.setTargetObjectId(appt.Account.PersonContactId);  // ← shadow Contact Id
        Id owaId = getOrgWideEmailId();
        if (owaId != null) {
            mail.setOrgWideEmailAddressId(owaId);
        }

                System.debug(mail);

        return mail;

    }

    /**
     * Builds a reminder email for 12h or 24h before the appointment.
     */
    private static Messaging.SingleEmailMessage buildReminderEmail(ServiceAppointment appt, Integer hoursAhead) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		//mail.setSenderDisplayName('OncoGlobal India');
        mail.setToAddresses(resolvePatientEmails(appt));
        mail.setCcAddresses(resolveDoctorEmails(appt));
        mail.setSubject('🔔 Reminder: Your Appointment is in ' + hoursAhead + ' Hours');
        mail.setHtmlBody(buildReminderHtml(appt, hoursAhead));
        mail.setSaveAsActivity(true);
        mail.setTargetObjectId(appt.Account.PersonContactId);  // ← shadow Contact Id
        Id owaId = getOrgWideEmailId();
        if (owaId != null) {
            mail.setOrgWideEmailAddressId(owaId);
        }
        System.debug(mail);

        return mail;
    }


    // ═════════════════════════════════════════════════════════════════════════
    //  HTML TEMPLATES
    // ═════════════════════════════════════════════════════════════════════════

    private static String buildConfirmationHtml(ServiceAppointment appt) {
        String patientName = appt.Account != null ? appt.Account.Name : 'Patient';
        String doctorName  = appt.Contact != null ? appt.Contact.Name  : 'Your Doctor';
        String doctorTitle = appt.Contact != null && String.isNotBlank(appt.Contact.Title)
                             ? appt.Contact.Title : 'Physician';

        return wrapInLayout(
            '✅ Appointment Confirmed',
            patientName,
            appt,
            doctorName,
            doctorTitle,
            '<div class="badge badge-success">Confirmed</div>',
            '<p class="intro-text">Your appointment has been successfully scheduled. '
            + 'Please find the details below and save them for your records.</p>',
            true  // show receipt button
        );
    }

    private static String buildReminderHtml(ServiceAppointment appt, Integer hoursAhead) {
        String patientName = appt.Account != null ? appt.Account.Name : 'Patient';
        String doctorName  = appt.Contact != null ? appt.Contact.Name  : 'Your Doctor';
        String doctorTitle = appt.Contact != null && String.isNotBlank(appt.Contact.Title)
                             ? appt.Contact.Title : 'Physician';

        String badgeClass   = hoursAhead == 24 ? 'badge-warning' : 'badge-alert';
        String badgeLabel   = 'In ' + hoursAhead + ' Hours';
        String introMessage = hoursAhead == 24
            ? 'This is a friendly reminder that you have an appointment scheduled tomorrow. '
              + 'Please ensure you have everything ready.'
            : 'Your appointment is just 12 hours away. Please prepare and be on time.';

        return wrapInLayout(
            '🔔 Appointment Reminder',
            patientName,
            appt,
            doctorName,
            doctorTitle,
            '<div class="badge ' + badgeClass + '">' + badgeLabel + '</div>',
            '<p class="intro-text">' + introMessage + '</p>',
            true
        );
    }

    /**
     * Master layout renderer — shared by all 3 email types.
     */
    private static String wrapInLayout(
        String  headline,
        String  patientName,
        ServiceAppointment appt,
        String  doctorName,
        String  doctorTitle,
        String  badgeHtml,
        String  introHtml,
        Boolean showReceiptBtn
    ) {
        String address      = formatAddress(appt);
        String startTime    = formatDateTime(appt.SchedStartTime);
        String endTime      = formatDateTime(appt.SchedEndTime);
        String subject      = String.isNotBlank(appt.Subject) ? appt.Subject : 'Medical Appointment';
        String receiptUrl   = String.isNotBlank(appt.ApptBookingInfoUrl) ? appt.ApptBookingInfoUrl : '#';

        String receiptSection = showReceiptBtn
            ? '<a href="' + receiptUrl + '" class="btn-receipt" target="_blank">'
              + '⬇ Download Appointment Receipt</a>'
            : '';

        return '<!DOCTYPE html>'
+ '<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
+ '<style>'
+ '  @import url(\'https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=DM+Serif+Display&display=swap\');'
+ '  *{margin:0;padding:0;box-sizing:border-box}'
+ '  body{font-family:\'DM Sans\',sans-serif;background:#f0f4f8;color:#1a202c}'
+ '  .wrapper{max-width:620px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;'
+ '           box-shadow:0 4px 24px rgba(0,0,0,0.08)}'

// ── Header bar ──
+ '  .header{background:linear-gradient(135deg,#0d47a1 0%,#1976d2 60%,#42a5f5 100%);'
+ '          padding:40px 36px 32px;text-align:center}'
+ '  .header-logo{font-family:\'DM Serif Display\',serif;font-size:13px;letter-spacing:3px;'
+ '               text-transform:uppercase;color:rgba(255,255,255,0.7);margin-bottom:18px}'
+ '  .header h1{font-family:\'DM Serif Display\',serif;font-size:28px;color:#ffffff;'
+ '             font-weight:400;line-height:1.3}'
+ '  .header .sub{font-size:13px;color:rgba(255,255,255,0.75);margin-top:8px;letter-spacing:0.5px}'

// ── Badge ──
+ '  .badge{display:inline-block;padding:5px 16px;border-radius:20px;font-size:12px;'
+ '         font-weight:600;letter-spacing:1px;text-transform:uppercase;margin:20px 0 0}'
+ '  .badge-success{background:rgba(255,255,255,0.2);color:#e8f5e9;border:1px solid rgba(255,255,255,0.35)}'
+ '  .badge-warning{background:rgba(255,193,7,0.25);color:#fff8e1;border:1px solid rgba(255,193,7,0.5)}'
+ '  .badge-alert{background:rgba(244,67,54,0.25);color:#ffebee;border:1px solid rgba(244,67,54,0.5)}'

// ── Body ──
+ '  .body{padding:36px 36px 28px}'
+ '  .greeting{font-size:17px;color:#2d3748;margin-bottom:8px;font-weight:500}'
+ '  .intro-text{font-size:14px;color:#718096;line-height:1.7;margin-bottom:28px}'

// ── Detail card ──
+ '  .card{background:#f7faff;border:1px solid #dce8fb;border-radius:12px;overflow:hidden;margin-bottom:24px}'
+ '  .card-title{background:#e8f0fe;padding:12px 20px;font-size:11px;font-weight:600;'
+ '              letter-spacing:1.5px;text-transform:uppercase;color:#3c5a9a}'
+ '  .detail-grid{display:table;width:100%;border-collapse:collapse}'
+ '  .detail-row{display:table-row}'
+ '  .detail-row:not(:last-child) .detail-label,'
+ '  .detail-row:not(:last-child) .detail-value{'
+ '    border-bottom:1px solid #e8effc}'
+ '  .detail-label{display:table-cell;padding:13px 20px;font-size:12px;font-weight:600;'
+ '                color:#8fa3c8;text-transform:uppercase;letter-spacing:0.8px;'
+ '                width:36%;vertical-align:middle}'
+ '  .detail-value{display:table-cell;padding:13px 20px;font-size:14px;color:#2d3748;'
+ '                font-weight:400;vertical-align:middle;line-height:1.5}'
+ '  .detail-value strong{font-weight:600;color:#1a202c}'

// ── Doctor card ──
+ '  .doctor-card{background:linear-gradient(135deg,#e8f0fe,#f0f4ff);'
+ '               border:1px solid #c5d5f5;border-radius:12px;padding:18px 20px;'
+ '               margin-bottom:24px;display:flex;align-items:center;gap:16px}'
+ '  .doctor-avatar{width:48px;height:48px;border-radius:50%;background:linear-gradient(135deg,#1565c0,#42a5f5);'
+ '                 display:inline-block;text-align:center;line-height:48px;'
+ '                 font-family:\'DM Serif Display\',serif;font-size:20px;color:#fff;flex-shrink:0;vertical-align:middle}'
+ '  .doctor-info .name{font-size:15px;font-weight:600;color:#1a202c}'
+ '  .doctor-info .title-role{font-size:12px;color:#5a7abf;margin-top:2px}'
+ '  .doctor-info .cc-note{font-size:11px;color:#90a4c0;margin-top:4px}'

// ── Receipt button ──
+ '  .btn-receipt{display:block;background:linear-gradient(135deg,#0d47a1,#1976d2);'
+ '               color:#ffffff !important;text-decoration:none;text-align:center;'
+ '               padding:15px 24px;border-radius:10px;font-size:14px;font-weight:600;'
+ '               letter-spacing:0.3px;margin:4px 0 24px;transition:opacity 0.2s}'

// ── Footer ──
+ '  .footer{background:#f7faff;border-top:1px solid #e2eaf7;padding:24px 36px;text-align:center}'
+ '  .footer p{font-size:12px;color:#a0aec0;line-height:1.7}'
+ '  .footer .org{font-weight:600;color:#8fa3c8;font-size:13px;margin-bottom:6px}'
+ '  .divider{height:1px;background:linear-gradient(to right,transparent,#c5d5f5,transparent);margin:4px 0 20px}'
+ '</style>'
+ '</head><body>'
+ '<div class="wrapper">'

// ─ Header ─
+ '  <div class="header">'
+ '    <div class="header-logo">OncoGlobal India</div>'
+ '    <h1>' + headline + '</h1>'
+ '    <div class="sub">' + subject + '</div>'
+      badgeHtml
+ '  </div>'

// ─ Body ─
+ '  <div class="body">'
+ '    <p class="greeting">Dear ' + escapeHtml(patientName) + ',</p>'
+      introHtml

// ─ Appointment Details Card ─
+ '    <div class="card">'
+ '      <div class="card-title">📋 Appointment Details</div>'
+ '      <div class="detail-grid">'
+ '        <div class="detail-row">'
+ '          <div class="detail-label">Appointment</div>'
+ '          <div class="detail-value"><strong>' + escapeHtml(subject) + '</strong></div>'
+ '        </div>'
+ '        <div class="detail-row">'
+ '          <div class="detail-label">Date &amp; Start</div>'
+ '          <div class="detail-value">' + escapeHtml(startTime) + '</div>'
+ '        </div>'
+ '        <div class="detail-row">'
+ '          <div class="detail-label">End Time</div>'
+ '          <div class="detail-value">' + escapeHtml(endTime) + '</div>'
+ '        </div>'
+ '        <div class="detail-row">'
+ '          <div class="detail-label">Location</div>'
+ '          <div class="detail-value">' + escapeHtml(address) + '</div>'
+ '        </div>'
+ '      </div>'
+ '    </div>'

// ─ Doctor Card ─
+ '    <div class="doctor-card">'
+ '      <div class="doctor-avatar">' + getInitials(doctorName) + '</div>'
+ '      <div class="doctor-info">'
+ '        <div class="name">' + escapeHtml(doctorName) + '</div>'
+ '        <div class="title-role">' + escapeHtml(doctorTitle) + '</div>'
+ '        <div class="cc-note">📧 Copied on this email</div>'
+ '      </div>'
+ '    </div>'

//  Receipt Button ─
+      receiptSection

+ '    <div class="divider"></div>'
+ '    <p style="font-size:13px;color:#718096;line-height:1.7">'
+ '      If you need to reschedule or have any questions, please contact our scheduling team '
+ '      at least 24 hours before your appointment.'
+ '    </p>'
+ '  </div>'

// ─ Footer ─
+ '  <div class="footer">'
+ '    <p class="org">OncoGlobal India — Appointment Services</p>'
+ '    <p>This is an automated notification. Please do not reply directly to this email.<br>'
+ '       © ' + String.valueOf(Date.today().year()) + ' All rights reserved.</p>'
+ '  </div>'
+ '</div>'
+ '</body></html>';
    }


    // ═════════════════════════════════════════════════════════════════════════
    //  HELPER METHODS
    // ═════════════════════════════════════════════════════════════════════════

    private static List<String> resolvePatientEmails(ServiceAppointment appt) {
        List<String> emails = new List<String>();
        if (appt.Account != null && String.isNotBlank(appt.Account.PersonEmail)) {
            emails.add(appt.Account.PersonEmail);
        }
        return emails;
    }

    private static List<String> resolveDoctorEmails(ServiceAppointment appt) {
        List<String> emails = new List<String>();
        if (appt.Contact != null && String.isNotBlank(appt.Contact.Email)) {
            emails.add(appt.Contact.Email);
        }
        return emails;
    }

    private static String formatAddress(ServiceAppointment appt) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(appt.Street))     parts.add(appt.Street);
        if (String.isNotBlank(appt.City))       parts.add(appt.City);
        if (String.isNotBlank(appt.State))      parts.add(appt.State);
        if (String.isNotBlank(appt.PostalCode)) parts.add(appt.PostalCode);
        if (String.isNotBlank(appt.Country))    parts.add(appt.Country);
        return parts.isEmpty() ? 'To be confirmed' : String.join(parts, ', ');
    }

    private static String formatDateTime(DateTime dt) {
        if (dt == null) return 'TBD';
        // Renders as: Monday, 28 April 2025 at 10:30 AM
		return dt.format('EEEE, d MMMM yyyy \'at\' h:mm a');    
    }

    private static String getInitials(String fullName) {
        if (String.isBlank(fullName)) return '?';
        List<String> parts = fullName.trim().split('\\s+');
        String initials = '';
        for (String part : parts) {
            if (initials.length() < 2 && part.length() > 0) {
                initials += part.substring(0, 1).toUpperCase();
            }
        }
        return initials;
    }

    private static String escapeHtml(String input) {
        if (String.isBlank(input)) return '';
        return input
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#x27;');
    }
    private static Id getOrgWideEmailId() {
    List<OrgWideEmailAddress> owa = [
        SELECT Id FROM OrgWideEmailAddress
        WHERE DisplayName = 'OncoGlobal India'
        LIMIT 1
    ];
    return owa.isEmpty() ? null : owa[0].Id;
	}
}