
function rewireLinks() {
//    jQuery('a.page-link.forward').click(function() {
//        var url = this.href;
//        jQuery('#availability-con').load(url + ' #availability', rewireLinks);
//        var stateObject = {date: "[% this_week %]"};
//        var path = url.replace(/\w+\/\/:[^\/]+/, '');
//        history.pushState(stateObject, this.id, path);
//        return false;
//    });

    jQuery('a.page-link.forward').click(function() {
        var url = this.href + ".table";
        that = this;
        var data = null;
        var width = jQuery('#availability-con').outerWidth();
        var success = function(data) {
            jQuery('#availability-con').css({overflow: "hidden"});
            var $results = jQuery(data);
            new Effect.Move('availability', {
                x: -width, 
                y: 0,
                mode: "relative",
                transition: Effect.Transitions.sinoidal,
                afterFinish: function() {
                    jQuery('#availability').remove();
                    $results.css({"position": "relative", "top": "0px", "left": width});
                    jQuery('#availability-con').append($results);
                    new Effect.Move('availability', {x: -width, y: 0, mode: "relative",transition: Effect.Transitions.sinoidal});
                }
            });
            updateLinkHrefs(that.href);
        };
        jQuery.get(url, data, success, "html");
        return false;
    });

    jQuery('a.page-link.back').click(function() {
        var url = this.href + ".table";
        that = this;
        var data = null;
        var width = jQuery('#availability-con').outerWidth();
        var success = function(data) {
            jQuery('#availability-con').css({overflow: "hidden"});
            var $results = jQuery(data);
            new Effect.Move('availability', {
                x: width, 
                y: 0,
                mode: "relative",
                transition: Effect.Transitions.sinoidal,
                afterFinish: function() {
                    jQuery('#availability').remove();
                    $results.css({"position": "relative", "top": "0px", "left": -width});
                    jQuery('#availability-con').append($results);
                    new Effect.Move('availability', {x: width, y: 0, mode: "relative", transition: Effect.Transitions.sinoidal});
                }
            });
            updateLinkHrefs(that.href);
        };
        jQuery.get(url, data, success, "html");
        return false;
    });
}

function updateLinkHrefs(currentHref) {
    var url = $BASE + "get_new_availability_hrefs";
    var data = {
        currentHref: currentHref
    };
    var success = function(results) {
        jQuery('#month-name').text(results.monthName);
        jQuery('#year').text(results.year);
        jQuery('a.page-link.back').attr("href", results.backLink);
        jQuery('a.page-link.forward').attr("href", results.fwdLink);
    };
    jQuery.getJSON(url, data, success);
}

jQuery(rewireLinks);

window.onpopstate = function(event) {
    var url = window.location.toString();
    jQuery('#availability-con').load(url + ' #availability', rewireLinks);
};

