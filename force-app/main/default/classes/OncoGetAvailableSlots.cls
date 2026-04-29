public without sharing class OncoGetAvailableSlots {

    public class SlotRequest {
        @InvocableVariable(required=true description='Doctor service resource name e.g. SR_Ananya_Rao')
        public String serviceResourceName;
        @InvocableVariable(required=true description='ServiceTerritory Id of the selected facility')
        public String serviceTerritoryId;
        @InvocableVariable(required=true description='WorkType name e.g. Follow-Up Review, New Patient Consultation')
        public String workTypeName;
        @InvocableVariable(required=true description='Preferred date for the appointment')
        public Date preferredDate;
    }

    public class SlotResponse {
        @InvocableVariable(description='Available time slots formatted for display')
        public String availableSlots;
        @InvocableVariable(description='Number of slots found')
        public Integer totalSlots;
        @InvocableVariable(description='Appointment duration in minutes')
        public Integer durationMinutes;
        @InvocableVariable(description='WorkType preparation instructions')
        public String prepInstructions;
        @InvocableVariable(description='Service resource name for re-querying')
        public String serviceResourceName;
        @InvocableVariable(description='Service territory Id for re-querying')
        public String serviceTerritoryId;
        @InvocableVariable(description='WorkType name for re-querying')
        public String workTypeName;
        @InvocableVariable(description='Doctor display name')
        public String doctorName;
    }

    public class SlotOutput {
        @InvocableVariable public SlotResponse slotResponse;
    }

    @InvocableMethod(label='Get Available Slots' description='Find available appointment slots based on doctor operating hours and existing bookings')
    public static List<SlotOutput> getAvailableSlots(List<SlotRequest> requests) {
        List<SlotOutput> responses = new List<SlotOutput>();

        for (SlotRequest req : requests) {
            SlotOutput out = new SlotOutput();
            out.slotResponse = new SlotResponse();

            if (req.preferredDate < Date.today()) {
                out.slotResponse.availableSlots = 'Please select a date from today onwards.';
                out.slotResponse.totalSlots = 0;
                responses.add(out);
                continue;
            }

            // Step 0: Smart ID resolution
            if (req.serviceTerritoryId != null && req.serviceTerritoryId.startsWith('08p')) {
                List<ServiceAppointment> apptLookup = [
                    SELECT ServiceTerritoryId, WorkType.Name
                    FROM ServiceAppointment
                    WHERE Id = :req.serviceTerritoryId
                    LIMIT 1
                ];
                if (!apptLookup.isEmpty()) {
                    req.serviceTerritoryId = apptLookup[0].ServiceTerritoryId;
                    req.workTypeName = apptLookup[0].WorkType.Name;

                    List<AssignedResource> arLookup = [
                        SELECT ServiceResource.Name
                        FROM AssignedResource
                        WHERE ServiceAppointmentId = :apptLookup[0].Id
                        LIMIT 1
                    ];
                    if (!arLookup.isEmpty()) {
                        req.serviceResourceName = arLookup[0].ServiceResource.Name;
                    }
                }
            }

            // Populate context fields for the LWC to re-query
            out.slotResponse.serviceResourceName = req.serviceResourceName;
            out.slotResponse.serviceTerritoryId = req.serviceTerritoryId;
            out.slotResponse.workTypeName = req.workTypeName;
            out.slotResponse.doctorName = 'Dr. ' + req.serviceResourceName.replace('SR_', '').replace('_', ' ');

            // Use shared logic
            SlotResult result = computeSlots(req.serviceResourceName, req.serviceTerritoryId, req.workTypeName, req.preferredDate);
            out.slotResponse.availableSlots = result.formatted;
            out.slotResponse.totalSlots = result.count;
            out.slotResponse.durationMinutes = result.duration;
            out.slotResponse.prepInstructions = result.prepInstructions;

            responses.add(out);
        }
        return responses;
    }

    /**
     * AuraEnabled method for the LWC to call when the user switches dates
     * in the date carousel — avoids a new agent prompt.
     */
    @AuraEnabled
    public static Map<String, Object> getSlotsForDate(String serviceResourceName, String serviceTerritoryId, String workTypeName, String dateStr) {
        Date selectedDate = Date.valueOf(dateStr);
        SlotResult result = computeSlots(serviceResourceName, serviceTerritoryId, workTypeName, selectedDate);

        Map<String, Object> response = new Map<String, Object>();
        response.put('availableSlots', result.formatted);
        response.put('totalSlots', result.count);
        response.put('durationMinutes', result.duration);
        response.put('prepInstructions', result.prepInstructions);
        response.put('dateLabel', selectedDate.format());
        return response;
    }

    // ── Shared logic ──────────────────────────────────────────────────

    private class SlotResult {
        String formatted = '';
        Integer count = 0;
        Integer duration = 0;
        String prepInstructions = '';
    }

    private static SlotResult computeSlots(String serviceResourceName, String serviceTerritoryId, String workTypeName, Date targetDate) {
        SlotResult result = new SlotResult();

        // WorkType
        List<WorkType> wtList = [
            SELECT Id, Name, EstimatedDuration, Description,
                   BlockTimeBeforeAppointment, BlockTimeAfterAppointment
            FROM WorkType
            WHERE Name = :workTypeName LIMIT 1
        ];
        if (wtList.isEmpty()) {
            result.formatted = 'Invalid appointment type.';
            return result;
        }

        WorkType wt = wtList[0];
        Integer duration = (Integer) wt.EstimatedDuration;
        Integer blockBefore = wt.BlockTimeBeforeAppointment != null ? (Integer) wt.BlockTimeBeforeAppointment : 0;
        Integer blockAfter = wt.BlockTimeAfterAppointment != null ? (Integer) wt.BlockTimeAfterAppointment : 0;
        Integer totalBlock = duration + blockBefore + blockAfter;
        result.duration = duration;
        result.prepInstructions = wt.Description;

        // Operating Hours
        String dayOfWeek = getDayOfWeek(targetDate);
        Id operatingHoursId = null;

        List<ServiceTerritoryMember> stmList = [
            SELECT OperatingHoursId
            FROM ServiceTerritoryMember
            WHERE ServiceTerritoryId = :serviceTerritoryId
            AND ServiceResource.Name = :serviceResourceName
            LIMIT 1
        ];
        if (!stmList.isEmpty() && stmList[0].OperatingHoursId != null) {
            operatingHoursId = stmList[0].OperatingHoursId;
        } else {
            List<ServiceTerritory> stList = [
                SELECT OperatingHoursId FROM ServiceTerritory
                WHERE Id = :serviceTerritoryId LIMIT 1
            ];
            if (!stList.isEmpty() && stList[0].OperatingHoursId != null) {
                operatingHoursId = stList[0].OperatingHoursId;
            }
        }

        if (operatingHoursId == null) {
            result.formatted = 'Could not find operating hours for this doctor at this facility.';
            return result;
        }

        List<TimeSlot> doctorSlots = [
            SELECT StartTime, EndTime FROM TimeSlot
            WHERE OperatingHoursId = :operatingHoursId
            AND DayOfWeek = :dayOfWeek AND Type = 'Normal'
        ];
        if (doctorSlots.isEmpty()) {
            result.formatted = 'The doctor does not have clinic hours on ' + dayOfWeek + '. Please try another date.';
            return result;
        }

        // Existing appointments — widen the query window by buffer times so that
        // appointments whose buffer zones bleed into this day are also caught.
        Id srId = [SELECT Id FROM ServiceResource WHERE Name = :serviceResourceName LIMIT 1].Id;
        DateTime dayStart = DateTime.newInstance(targetDate, Time.newInstance(0, 0, 0, 0))
                                .addMinutes(-blockAfter);   // catch appts whose blockAfter reaches into today
        DateTime dayEnd   = DateTime.newInstance(targetDate, Time.newInstance(23, 59, 59, 0))
                                .addMinutes(blockBefore);   // catch appts whose blockBefore reaches back into today

        List<ServiceAppointment> existingAppts = [
            SELECT SchedStartTime, SchedEndTime, Status FROM ServiceAppointment
            WHERE Id IN (SELECT ServiceAppointmentId FROM AssignedResource WHERE ServiceResourceId = :srId)
            AND SchedStartTime >= :dayStart AND SchedStartTime <= :dayEnd
            AND Status != 'Canceled'
            ORDER BY SchedStartTime
        ];

        // Calculate windows
        String formatted = '';
        Integer count = 0;
        for (TimeSlot ts : doctorSlots) {
            DateTime windowStart = DateTime.newInstance(targetDate, ts.StartTime);
            DateTime windowEnd = DateTime.newInstance(targetDate, ts.EndTime);
            DateTime slotStart = windowStart;

            while (slotStart.addMinutes(totalBlock) <= windowEnd && count < 8) {
                DateTime slotEnd = slotStart.addMinutes(duration);

                // The effective occupied zone of the NEW slot includes its buffer:
                //   [slotStart - blockBefore,  slotEnd + blockAfter]
                DateTime newEffectiveStart = slotStart.addMinutes(-blockBefore);
                DateTime newEffectiveEnd   = slotEnd.addMinutes(blockAfter);

                Boolean hasConflict = false;
                for (ServiceAppointment existing : existingAppts) {
                    // The effective occupied zone of the EXISTING appointment:
                    //   [SchedStartTime - blockBefore,  SchedEndTime + blockAfter]
                    DateTime existEffStart = existing.SchedStartTime.addMinutes(-blockBefore);
                    DateTime existEffEnd   = existing.SchedEndTime.addMinutes(blockAfter);

                    // Standard overlap: two intervals [A,B) and [C,D) overlap iff A < D && B > C
                    if (newEffectiveStart < existEffEnd && newEffectiveEnd > existEffStart) {
                        hasConflict = true;
                        break;
                    }
                }
                if (!hasConflict) {
                    count++;
                    formatted += count + '. ' + targetDate.format() + ' — ';
                    formatted += slotStart.format('h:mm a') + ' to ' + slotEnd.format('h:mm a');
                    formatted += ' (' + duration + ' min)';
                    // Append GMT ISO timestamp so the LWC can send the exact DateTime
                    formatted += '|' + slotStart.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\n';
                }
                slotStart = slotStart.addMinutes(30);
            }
        }

        if (count == 0) {
            formatted = 'No available slots on ' + targetDate.format() + '. Please try another date.';
        }

        result.formatted = formatted;
        result.count = count;
        return result;
    }

    private static String getDayOfWeek(Date d) {
        DateTime dt = DateTime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        return dt.format('EEEE');
    }
}
