var Payout = new function() {
  var self = this;
  var selectedState = '';

  self.updateAccount = function () {  
    var checkStatus = 'false';
    if (jQuery('input[name=commcardtype]').is(':checked')) {
      checkStatus="true";
    }
    var JSONObj = { 
      'contact': {
        'name': jQuery('#payout input[name=ps_contact_name]').val(),
        'company': jQuery('#payout input[name=ps_contact_company]').val(),
        'address1': jQuery('#payout input[name=ps_contact_address_1]').val(),
        'address2': jQuery('#payout input[name=ps_contact_address_2]').val(),
        'city': jQuery('#payout input[name=ps_contact_city]').val(),
        'state': jQuery('#payout select[name=payout_state]').val(),
        'country': jQuery('#payout select[name=payout_country]').val(),
        'postal_code': jQuery('#payout input[name=ps_contact_postal_code]').val(),
        'fax': jQuery('#payout input[name=ps_contact_fax]').val(),
        'phone': jQuery('#payout input[name=ps_contact_phone]').val(),
        'email': jQuery('#payout input[name=ps_contact_email]').val()
      },
      'payment_data': {
        'routing_number': jQuery('#payout input[name=ach_routing_number]').val(),
        'account_number': jQuery('#payout input[name=ach_account_number]').val(),
        'accountType': checkStatus
      },
    };
    self.sendData(JSONObj);
  };

  self.sendData = function(hash) {
    Tools.json({  url: '/admin/api/reseller/profile/payout/',
      method: 'PUT',
      data: hash,
      key: 'Payout',
      callback: function(content){
        var data = content['content']['info'];  
        jQuery('#existingData').removeClass('hidden').removeClass('rt-hidden');
        jQuery('span[name=payout_account_num]').text(data['payment_data']['account_number']);
        jQuery('span[name=payout_routing_num]').text(data['payment_data']['routing_number']);
        jQuery('#payout input[name=pt_gateway_account]').val(data['gatewayAccountName']);
        jQuery('#payout input[name=ps_contact_name]').val(data['contact']['name']);
        jQuery('#payout input[name=ps_contact_company]').val(data['contact']['company']);
        jQuery('#payout input[name=ps_contact_address_1]').val(data['contact']['address1']);
        jQuery('#payout input[name=ps_contact_address_2]').val(data['contact']['address2']);
        jQuery('#payout input[name=ps_contact_city]').val(data['contact']['city']);
        jQuery('#payout select[name=payout_country]').val(data['contact']['country']);
        jQuery('#payout input[name=ps_contact_postal_code]').val(data['contact']['postal_code']);
        jQuery('#payout input[name=ps_contact_fax]').val(data['contact']['fax']);
        jQuery('#payout input[name=ps_contact_phone]').val(data['contact']['phone']);
        jQuery('#payout input[name=ps_contact_email]').val(data['contact']['email']);
        jQuery('#payout input[name=ach_routing_number]').val('');
        jQuery('#payout input[name=ach_account_number]').val('');
        jQuery('#payout span[name="pay_account_type"]').text(data['payment_data']['accountType']);

        self.selectedState = data['contact']['state']

        var options = new Object();
        options['country'] = data['contact']['country'];
        options['selected'] = data['contact']['state'];
        options['name'] = 'select[name=payout_state]';
        getStates(options);

        var messageOptions = new Object();
        messageOptions['class'] = 'successMessage';
        messageOptions['message'] = 'Payout Information was successfully updated!';
        messageOptions['span'] = 'payoutArea';
        apiMessage(messageOptions);
      },
      error: function() {
        var messageOptions = new Object();
        messageOptions['class'] = 'failureMessage';
        messageOptions['message'] = 'An error occured when trying to update payout info.';
        messageOptions['span'] = 'payoutArea';
        apiMessage(messageOptions);
      }
    });
  };
};
