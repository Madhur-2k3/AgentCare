public without sharing class OncoGetAvailableSlots {

    public class SlotRequest {
        @InvocableVariable(required=true description='Doctor service resource name e.g. SR_Ananya_Rao')
        public String serviceResourceName;
        @InvocableVariable(required=true description='ServiceTerritory Id of the selected facility')
        public String serviceTerritoryId;
        @InvocableVariable(required=true description='WorkType name e.g. Follow-Up Review, New Patient Consultation')
        public String workTypeName;
        @InvocableVariable(required=true description='Preferred date for the appointment (at least 2 days from today)')
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
    }

    @InvocableMethod(label='Get Available Slots' description='Find available appointment slots based on doctor operating hours and existing bookings')
    public static List<SlotResponse> getAvailableSlots(List<SlotRequest> requests) {
        List<SlotResponse> responses = new List<SlotResponse>();

        for (SlotRequest req : requests) {
            SlotResponse res = new SlotResponse();

            if (req.preferredDate < Date.today().addDays(2)) {
                res.availableSlots = 'Please select a date at least 2 days from today.';
                res.totalSlots = 0;
                responses.add(res);
                continue;
            }

            // Step 1: Get WorkType info directly
            List<WorkType> wtList = [
                SELECT Id, Name, EstimatedDuration, Description,
                       BlockTimeBeforeAppointment, BlockTimeAfterAppointment
                FROM WorkType
                WHERE Name = :req.workTypeName LIMIT 1
            ];

            if (wtList.isEmpty()) {
                res.availableSlots = 'Invalid appointment type.';
                res.totalSlots = 0;
                responses.add(res);
                continue;
            }

            WorkType wt = wtList[0];
            Integer duration = (Integer) wt.EstimatedDuration;
            Integer blockBefore = wt.BlockTimeBeforeAppointment != null ? (Integer) wt.BlockTimeBeforeAppointment : 0;
            Integer blockAfter = wt.BlockTimeAfterAppointment != null ? (Integer) wt.BlockTimeAfterAppointment : 0;
            Integer totalBlock = duration + blockBefore + blockAfter;
            res.durationMinutes = duration;
            res.prepInstructions = wt.Description;

            // Step 2: Get doctor's operating hours for the day
            String dayOfWeek = getDayOfWeek(req.preferredDate);

            // Try doctor's personal operating hours first
            Id operatingHoursId = null;

            List<ServiceTerritoryMember> stmList = [
                SELECT OperatingHoursId
                FROM ServiceTerritoryMember
                WHERE ServiceTerritoryId = :req.serviceTerritoryId
                AND ServiceResource.Name = :req.serviceResourceName
                LIMIT 1
            ];

            if (!stmList.isEmpty() && stmList[0].OperatingHoursId != null) {
                // Use doctor's personal clinic hours
                operatingHoursId = stmList[0].OperatingHoursId;
            } else {
                // Fallback: use facility operating hours from ServiceTerritory
                List<ServiceTerritory> stList = [
                    SELECT OperatingHoursId
                    FROM ServiceTerritory
                    WHERE Id = :req.serviceTerritoryId
                    LIMIT 1
                ];
                if (!stList.isEmpty() && stList[0].OperatingHoursId != null) {
                    operatingHoursId = stList[0].OperatingHoursId;
                }
            }

            if (operatingHoursId == null) {
                res.availableSlots = 'Could not find operating hours for this doctor at this facility.';
                res.totalSlots = 0;
                responses.add(res);
                continue;
            }

            List<TimeSlot> doctorSlots = [
                SELECT StartTime, EndTime
                FROM TimeSlot
                WHERE OperatingHoursId = :operatingHoursId
                AND DayOfWeek = :dayOfWeek
                AND Type = 'Normal'
            ];

            if (doctorSlots.isEmpty()) {
                res.availableSlots = 'The doctor does not have clinic hours on ' + dayOfWeek + '. Please try another date.';
                res.totalSlots = 0;
                responses.add(res);
                continue;
            }

            // Step 3: Get existing appointments on that date
            Id srId = [SELECT Id FROM ServiceResource WHERE Name = :req.serviceResourceName LIMIT 1].Id;
            DateTime dayStart = DateTime.newInstance(req.preferredDate, Time.newInstance(0, 0, 0, 0));
            DateTime dayEnd = DateTime.newInstance(req.preferredDate, Time.newInstance(23, 59, 59, 0));

            List<ServiceAppointment> existingAppts = [
                SELECT SchedStartTime, SchedEndTime
                FROM ServiceAppointment
                WHERE Id IN (SELECT ServiceAppointmentId FROM AssignedResource WHERE ServiceResourceId = :srId)
                AND SchedStartTime >= :dayStart AND SchedStartTime <= :dayEnd
                AND Status != 'Canceled'
                ORDER BY SchedStartTime
            ];

            // Step 4: Calculate available windows
            String formatted = '';
            Integer count = 0;

            for (TimeSlot ts : doctorSlots) {
                DateTime windowStart = DateTime.newInstance(req.preferredDate, ts.StartTime);
                DateTime windowEnd = DateTime.newInstance(req.preferredDate, ts.EndTime);

                DateTime slotStart = windowStart;
                while (slotStart.addMinutes(totalBlock) <= windowEnd && count < 5) {
                    DateTime slotEnd = slotStart.addMinutes(duration);

                    Boolean hasConflict = false;
                    for (ServiceAppointment existing : existingAppts) {
                        if (slotStart < existing.SchedEndTime && slotEnd > existing.SchedStartTime) {
                            hasConflict = true;
                            break;
                        }
                    }

                    if (!hasConflict) {
                        count++;
                        formatted += count + '. ' + req.preferredDate.format() + ' — ';
                        formatted += slotStart.format('h:mm a') + ' to ' + slotEnd.format('h:mm a');
                        formatted += ' (' + duration + ' min)\n';
                    }

                    slotStart = slotStart.addMinutes(30);
                }
            }

            if (count == 0) {
                formatted = 'No available slots on ' + req.preferredDate.format() + '. Please try another date.';
            }

            res.availableSlots = formatted;
            res.totalSlots = count;
            responses.add(res);
        }
        return responses;
    }

    private static String getDayOfWeek(Date d) {
        DateTime dt = DateTime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        return dt.format('EEEE');
    }
}
