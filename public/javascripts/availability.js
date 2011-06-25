
function rewireLinks() {
//    jQuery('a.page-link.forward').click(function() {
//        var url = this.href;
//        jQuery('#availability-con').load(url + ' #availability', rewireLinks);
//        var stateObject = {date: "[% this_week %]"};
//        var path = url.replace(/\w+\/\/:[^\/]+/, '');
//        history.pushState(stateObject, this.id, path);
//        return false;
//    });

    var $fwdLink = jQuery('a.page-link.forward');
    var $backLink = jQuery('a.page-link.back');
    $fwdLink.unbind('click');
    $backLink.unbind('click');
    $fwdLink.click(getSlider($fwdLink.attr("href"), true));
    $backLink.click(getSlider($backLink.attr("href"), false));
}

function getSlider(href, isFwd) {
    return function() {
        var url = href + ".table";
        var data = null;
        var width = jQuery('#availability-con').outerWidth();
        var success = function(response) {
            jQuery('#availability-con').css({overflow: "hidden"});
            var $results = jQuery(response);
            new Effect.Move('availability', {
                x: (isFwd) ? -width : width, 
                y: 0,
                mode: "relative",
                transition: Effect.Transitions.sinoidal,
                afterFinish: function() {
                    jQuery('#availability').remove();
                    var leftPos = (isFwd) ? width : -width;
                    var leftDelta = (isFwd) ? -width : width;
                    $results.css({"position": "relative", "top": "0px", "left": leftPos});
                    jQuery('#availability-con').append($results);
                    new Effect.Move('availability', {x: leftDelta, y: 0, mode: "relative", transition: Effect.Transitions.sinoidal});
                }
            });
            updateLinkHrefs(href);
            var path = href.replace(/\w+\/\/:[^\/]+/, '');
            var stateObject = {path: path};
            history.pushState(stateObject, path, path);
        };
        jQuery.get(url, data, success, "html");
        return false;
    };
}

function updateLinkHrefs(currentHref) {
    var url = $BASE + "get_new_hrefs";
    var data = {
        currentHref: currentHref
    };
    var success = function(results) {
        jQuery('#month-name').text(results.monthName);
        jQuery('#year').text(results.year);
        jQuery('a.page-link.back').attr("href", results.backLink);
        jQuery('a.page-link.forward').attr("href", results.fwdLink);
        rewireLinks();
    };
    jQuery.getJSON(url, data, success);
}

jQuery(rewireLinks);

window.onpopstate = function(event) {
    var url = window.location.toString();
    jQuery('#availability-con').load(url + ' #availability', rewireLinks);
};

