var last_selected;
var DISABLED = "disabled";

function setButtonState() {
    var selector = '.period-controls';
    if (jQuery('.cal-selected.day-half').length) {
        jQuery(selector).attr(DISABLED, false);
    } else {
        jQuery(selector).attr(DISABLED, true);
    }
}

function getClassAndText(period) {
    var cssClass = "allocated-" 
                    + period.category.replace(/[^A-Za-z0-9]+/g, '-');
    var text = (period.note) ? period.note : period.category.replace(/\/.*/, "");
    return {cssClass: cssClass, text: text};
}

var getAllocatedClasses = function(idx, cn) {
    var currentClasses = cn.split(' ');
    var ret = [];
    for (var i=0,l=currentClasses.length;i<l;i++) {
        if (currentClasses[i].match(/allocated/)) {
        ret.push(currentClasses[i]);
        }
    }
    return ret.join(" ");
};

function sendPeriodRequest(ids) {
    jQuery.ajax({
        headers: {
            authorization: $AUTH
        },
        type: "POST",
        traditional: true,
        url: $BASE + "add_period",
        data: {
            user: $USER,
            half_days: ids,
            note: jQuery('#period-reason').val(),
            category: jQuery('#period-category').val()
        },
        dataType: "json",
        success: function(data) {
            var allocatedIds = data.ids;
                
            var parsed = getClassAndText(data);
            for (var i=0, l=allocatedIds.length;i<l;i++) {
                var id = allocatedIds[i];
                var halfDay = jQuery('#' + id)
                            .removeClass('cal-selected')
                            .removeClass(getAllocatedClasses)
                            .text("");
                if (data.category !== "REMOVE") {
                    halfDay.removeClass('cal-selected')
                            .addClass(parsed.cssClass)
                            .text(parsed.text);
                }
            }
            if (! data.all_added) {
                if (data.category === "REMOVE") {
                    alert("Sorry, you can only cancel leave periods that haven't already occurred. Past periods can be edited, but not cancelled.");
                } else {
                    alert("Sorry, not all your requested leave could be allocated. You may only allocate business away periods, and vaction time within your holiday allowance");
                }
            }
            setButtonState();
        }
    });
}

jQuery(function() {
    jQuery('#clear-all').click(function() {
        jQuery('.day-half').removeClass("cal-selected");
        setButtonState();
    });
    jQuery('.cal-week.cal-cell').click(function() {
        var parts = this.id.split("-");
        var dates = parts[2].split(":");
        var startDate = dates[0];
        var endDate = dates[1];
        var halfDays = jQuery('.day-half');
        var startString = [parts[0], parts[1], startDate, "aa"].join("-");
        var endString = [parts[0], parts[1], endDate, "zz"].join("-");
        halfDays.filter(function() {
            if ((this.id.localeCompare(startString) >= 0)
                && (this.id.localeCompare(endString) <= 0)) {
                return true;
            } 
            return false;
        }).toggleClass("cal-selected");
        setButtonState();
    });
    jQuery('#add-period').click(function(ev) {
        var selected = jQuery('.cal-selected.day-half');
        var ids = selected.map(function() {
            return this.id;
            }).get();
        sendPeriodRequest(ids);
    });
    jQuery('.day-half').click(function(ev) {
        var selectedClass = 'cal-selected';
        if (ev.shiftKey) {
            var halfDays = jQuery('.day-half');
            var sortingUp = (this.id >= last_selected);
            console.log("Sorting up");
            var that = this;
            halfDays.each(function(idx, elem) {
                if (sortingUp) {
                    if ((elem.id > last_selected) && (elem.id <= that.id)) {
                        jQuery(elem).toggleClass(selectedClass);
                    }
                } else {
                    if (elem.id < last_selected && elem.id >= that.id) {
                        jQuery(elem).toggleClass(selectedClass);
                    }
                }
            });
        } else {
            jQuery(this).toggleClass('cal-selected');
        }
        last_selected = this.id;
        setButtonState();
        return false;
    });
});
