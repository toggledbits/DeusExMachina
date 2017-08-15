//# sourceURL=J_DeusExMachinaII1_ALTUI.js
"use strict";

var DeusExMachina_ALTUI = ( function( window, undefined ) {

        function _draw( device ) {
                var html ="";
                var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DeusExMachinaII1", "Message");
                var st = MultiBox.getStatus( device, "urn:upnp-org:serviceId:SwitchPower1", "Status");
                html += '<div class="pull-left">';
                html += message;
                html += "</div>";
                html += ALTUI_PluginDisplays.createOnOffButton( st, "toggledbits-deus-" + device.altuiid, _T("Disabled,Enabled"), "pull-right");
                html += "<script type='text/javascript'>";
                html += "$('div#toggledbits-deus-{0}').on('click', function() { DeusExMachina_ALTUI.toggleEnable('{0}','div#toggledbits-deus-{0}'); } );".format(device.altuiid);
                html += "</script>";
                return html;
        }
    return {
        DeviceDraw: _draw,
        toggleEnable: function (altuiid, htmlid) {
                ALTUI_PluginDisplays.toggleButton(altuiid, htmlid, 'urn:upnp-org:serviceId:SwitchPower1', 'Status', function(id,newval) {
                        MultiBox.runActionByAltuiID( altuiid, 'urn:upnp-org:serviceId:SwitchPower1', 'SetTarget', {newTargetValue:newval} );
                });
        },
    };
})( window );
