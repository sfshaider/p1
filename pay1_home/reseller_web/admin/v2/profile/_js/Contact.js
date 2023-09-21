var Contact = new function() {
  var self = this;
  var selectedState = '';
 
  self.updateContact = function () {
    function i(field) {
      return jQuery('#contact input[name=' + field + ']').val();
    }

    function s(field) {
      return jQuery('#contact select[name=' + field + '] option:selected').val();
    }

    var JSONObj = { 
      "account": {
        "contact": {
        'name': i('ps_contact_name'),
        'company': i('ps_contact_company'),
        'address1': i('ps_contact_address_1'),
        'address2': i('ps_contact_address_2'),
        'city': i('ps_contact_city'),
        'state': s('ps_contact_state'),
        'country': s('ps_contact_country'),
        'postalCode': i('ps_contact_postal_code'),
        'phone': i('ps_contact_phone'),
        'fax': i('ps_contact_fax'),
        'email': i('ps_contact_email'),
        'company': i('ps_contact_company')
      },
      "tech": {
        'name': i('ps_tech_name'),
        'phone': i('ps_tech_phone'),
        'email': i('ps_tech_email')
       },
       "billing":{
         'email': i('ps_billing_email')
        },
        'url': i('ps_contact_url')
        },
        'password': {
          'newPassword': i('pt_gateway_password'),
          'checkPassword': i('pt_gateway_password_check'),
          'oldPassword': i('pt_old_password')
        }
    };

    self.sendData(JSONObj);
  };

  self.sendData  = function (hash){
    function i(field,value) {
      jQuery('#contact input[name=' + field + ']').val(value);
    }

    function s(field,value,callback) {
      jQuery('#contact select[name=' + field + ']').val(value);
    }

    Tools.json({ url: '/admin/api/reseller/profile/contact/',
      action:'update',
      data:hash,
      key: 'Contact',
      callback: function(content) {
        var data = content['content'];
        i('ps_contact_name',data['account']['contact']['name']);
        i('ps_contact_company',data['account']['contact']['company']);
        i('ps_contact_address_1',data['account']['contact']['address1']);
        i('ps_contact_address_2',data['account']['contact']['address2']);
        i('ps_contact_city',data['account']['contact']['city']);
        s('ps_contact_country',data['account']['contact']['country']);
        i('ps_contact_postal_code',data['account']['contact']['postalCode']);
        i('ps_contact_phone',data['account']['contact']['phone']);
        i('ps_contact_fax',data['account']['contact']['fax']);
        i('ps_contact_email',data['account']['contact']['email']);
        i('ps_billing_email',data['account']['billing']['email']);
        i('ps_tech_email',data['account']['tech']['email']);
        i('ps_tech_phone',data['account']['tech']['phone']);
        i('ps_tech_name',data['account']['tech']['name']);
        i('ps_contact_url',data['account']['url']);
        self.selectedState =  data['account']['contact']['state'];
          
        //Password
        i('pt_gateway_password','');
        i('pt_gateway_password_check','');
        i('pt_old_password','');
        if (data['account']['password'] != null && data['account']['password'] == 'fail'){
          jQuery('#badPassChange').removeClass('rt-hidden');
          jQuery('#contact input[name=pt_old_password]').focus();
        } else {
          jQuery('#badPassChange').addClass('rt-hidden');
          var messageOptions = new Object();
          messageOptions['class'] = 'successMessage';
          messageOptions['message'] = 'Contact Information was successfully updated!';
          messageOptions['span'] = 'contactArea';
          apiMessage(messageOptions);
      }
    },
    error: function() {
      var messageOptions = new Object();
      messageOptions['class'] = 'failureMessage';
      messageOptions['message'] = 'An error occured when trying to update contact info.';
      messageOptions['span'] = 'contactArea';

      apiMessage(messageOptions);
    }
   });

   Tools.json({ url: '/admin/api/country/:' + jQuery('#contact select[name=ps_contact_country]').val()  + '/state',
     method:'GET',
     callback: function(data) {
       var stateList = data['content']['states'];
       var stateOptions = new Object();
       for (var i in stateList) {
         stateOptions[stateList[i]['abbreviation']] = stateList[i]["commonName"];
       }

       Tools.selectOptions({ selectOptions: stateOptions, selectorName: 'select[name=ps_contact_state]', selected: self.selectedState });
     }
   });

  };
};
