var BillAuth = new function() {
  var self = this;

  self.authorize = function () {
    var JSONOBj;
  
    if (jQuery('input[name=ps_billing_type]:checked').val() == 'credit') {
      var checkBox = "false";
      var isBusiness = "false";
      if( jQuery('#billing input[name=tac_accept_box]').prop('checked')){
        checkBox = "true";
      }
      if(jQuery('#billing input[name=isBusinessCard]').prop('checked')){
        isBusiness = "true";
      }

      JSONObj = {
        'billing_type':'credit',
        'payment_data':{
          'card_number': jQuery('#billing input[name=pt_card_number]').val(),
          'exp_month': jQuery('#billing select[name=pt_card_exp_month]').val(),
          'exp_year': jQuery('#billing select[name=pt_card_exp_year]').val(),
          'business_account': isBusiness
        },
        'full_name': jQuery('#billing input[name=ps_contact_name]').val(),
        'tax_id': jQuery('#billing input[name=ps_tax_id]').val(),
        'tac': checkBox
      };
    } else if(jQuery('input[name=ps_billing_type]:checked').val() == 'ach') {
      var checkBox = "false";
      var isBusiness = "false";
      if( jQuery('#billing input[name=tac_accept_box]').prop('checked')){
        checkBox = "true";
      }
    
      if (jQuery('#billing input[name=isBusinessACHAccount]').prop('checked')){
        isBusiness = "true";
      }

      JSONObj = {
        'billing_type':'ach',
        'payment_data':{
          'bank': jQuery('#billing input[name=ps_bank_name]').val(),
          'routing': jQuery('#billing input[name=ach_routing_number]').val(),
          'account': jQuery('#billing input[name=ach_account_number]').val(),
          'business_account': isBusiness
        },
        'full_name': jQuery('#billing input[name=ps_contact_name]').val(),
        'tax_id': jQuery('#billing input[name=ps_tax_id]').val(),
        'tac': checkBox
      };
    }
  
    self.sendData(JSONObj);
  };

  self.sendData = function(hash) {
    Tools.json({ url: '/admin/api/reseller/profile/billauth/',
     method: 'PUT',
     data: hash,
     key: 'BillAuth',
     callback: function(content) {
       var data = content['content']['info'];
       if(data['status'] == 'success'){
         var billType = data['billing_info']['billing_type'];
         var accountInfo = "";
         if(billType == "Credit") {
           accountInfo = "<span class='paymentAgree'>Card Number: </span><span>" + data['billing_info']['enccard'] + '</span><br><span class="paymentAgree">Exp Date: </span><span>';
           accountInfo += data['billing_info']['exp_date'] + '</span>';
         } else if (billType == "Checking"){
           accountInfo = "<span class='paymentAgree'>Routing Number: </span><span>" + data['billing_info']['routing'] + "</span> <br>";
           accountInfo += "<span class='paymentAgree'>Account Number: </span><span>" + data['billing_info']['account'] + "</span>";
         }

         jQuery('#billing input[name=pt_card_number]').val('');
         jQuery('#billing input[name=ps_contact_name]').val(data['full_name']);
         jQuery('#billing input[name=ps_tax_id]').val('');
         jQuery('#billing input[name=isBusinessCard]').prop('checked',false).change();
         jQuery('#billing input[name=ps_bank_name]').val('');
         jQuery('#billing input[name=ach_routing_number]').val('');
         jQuery('#billing input[name=ach_account_number]').val('');
         jQuery('#billing input[name=isBusinessACHAccount]').prop('checked',false).change();
         jQuery('#billing input[name=tac_accept_box]').prop('checked',false).change();
         jQuery('#billing span[name=current_bill_info]').text(billType);
         jQuery('#billingAccountInfo').children().remove();
         jQuery('#billingAccountInfo').append(accountInfo);
 
         var messageOptions = new Object();
         messageOptions['class'] = 'successMessage';
         messageOptions['message'] = 'Billing Authorization information was successfully changed!';
         messageOptions['span'] = 'billAuthArea';
         apiMessage(messageOptions);
         jQuery('#tacFailure').addClass('rt-hidden');
       } else {
         jQuery('input[tac_accept_box]').focus();
         jQuery('#tacFailure').removeClass('rt-hidden');
       }
     },
     error: function() {
       var messageOptions = new Object();
       messageOptions['class'] = 'failureMessage';
       messageOptions['message'] = 'An error occured when trying to change billing authorization information.';
       messageOptions['span'] = 'billAuthArea';
       apiMessage(messageOptions);
     }
   });
  };
};
