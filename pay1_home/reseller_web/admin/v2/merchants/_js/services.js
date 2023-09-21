var Services = new function() {
  var self = this;

  self.setServiceButtonSettings = function(settings) {
    var id = settings.id;
    var mode = settings.mode;
    var disabled = false;
    var value = mode;
    if (value === 'request' || value === "" || value === null) {
      value = 'request setup';
    }

    if (mode === 'pending' || mode === 'enabled') {
      disabled = true
      jQuery('#'+id).click(function() {});
    } else {
      jQuery('#'+id).click(function() {
        var merchant = jQuery('#'+id).attr('merchant')
        var service  = jQuery('#'+id).attr('service')
        jQuery('#'+id).prop('disabled', disabled);
        self.requestService(merchant,service,id);
      })
    }

    // uppercase the first letter of the value
    value = value.charAt(0).toUpperCase() + value.slice(1)

    jQuery('#'+id).prop('disabled', disabled).val(value);
  }

  self.requestService = function(merchant,service,id) {
    Tools.json({ 'url':'/admin/api/reseller/merchant/:' + merchant + '/service/:' + service + '/request',
        'action': 'create',
           'key': 'requestService',
          'data': null,
      'onSuccess': function(responseData) {
        self.setServiceButtonSettings({ id: id, mode: 'pending' });
      }
    });
  }

  self.setAutoBatch = function(autoBatchValue) {
    console.log('setting auto batch to ' + autoBatchValue);
    var merchant = jQuery('#autoBatch').attr('merchant')
    Tools.json({ 'url':'/admin/api/reseller/merchant/:' + merchant + '/service/autobatch',
        'action': 'update',
           'key': 'requestService',
          'data': { 'autoBatch': autoBatchValue },
      'onError': function(responseData) {
        alert('Oops, something went wrong.  If this error persists, please contact support.  This page will be reloaded.');
        location.reload();
      }
    });
  }
}
