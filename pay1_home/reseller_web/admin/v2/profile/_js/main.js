google.load('visualization', '1', {packages:["table"]});

jQuery(document).ready(function() {
  jQuery('#tabs').tabs();
  Contact.selectedState = jQuery('select[name=ps_contact_state]').val();
  Payout.selectedState = jQuery('select[name=payout_state]').val();

  //Check if passwords match  
  jQuery('input[name=pt_gateway_password]').keyup(function() {
    passCheck();
  });
  
  jQuery('input[name=pt_gateway_password_check]').keyup(function() {
    passCheck();
  });
  //Refresh state list on country change
  jQuery('select[name=ps_contact_country]').change(function() {
    var options = new Object();
    options['country'] = jQuery(this).val();
    options['selected'] = Contact.selectedState;
    options['name'] = 'select[name=ps_contact_state]';
    getStates(options);
  });

  jQuery('select[name=payout_country]').change(function() {
    var options = new Object();
    options['country'] = jQuery(this).val();
    options['selected'] = Payout.selectedState;
    options['name'] = 'select[name=payout_state]';
    getStates(options);
  });

  jQuery('input[name=contactsubmit]').click(function() {
    if (jQuery('input[name=contactsubmit]').is(':disabled') ) {
      jQuery('input[name=pt_gateway_password]').focus();
    }
  });

  jQuery('input[name=contactsubmit]').click(function() {
    Contact.updateContact();
  });

  jQuery('input[name=payoutSubmit]').click(function() {
    Payout.updateAccount();
  });
    
  jQuery('input[name=billAuthSubmit]').click(function() {
    BillAuth.authorize();
  });

  jQuery('select[name=reseller_rates]').change( function () {
    BuyRates.getRates();
  });

  Tools.convertToGoogleTable({tableSelector:'#buyratesTable'});

});

function passCheck () {
  var newPass = jQuery('input[name=pt_gateway_password]').val();
  var confirmPass = jQuery('input[name=pt_gateway_password_check]').val(); 
  if (newPass.length > 0 || confirmPass.length > 0 ){
    if (newPass == confirmPass ) {
      jQuery('input[name=contactsubmit]').prop('disabled',false);
      jQuery('label[name=errorMessage]').removeClass('error').addClass('hidden');
    } else {
      jQuery('input[name=contactsubmit]').prop('disabled',true);
      if (confirmPass.length >0){
        jQuery('label[name=errorMessage]').removeClass('hidden').addClass('error');
      }
    } 
  } else {
    jQuery('input[name=contactsubmit]').prop('disabled',false);
    jQuery('label[name=errorMessage]').removeClass('error').addClass('hidden');
  }
};

function getStates(options) {
  var country = options['country'];
  var selectorName = options['name'];
  var selectorState = options['selected'];

  Tools.json({ url: '/admin/api/country/:' + country +'/state',
   method: 'GET',
   callback: function(responseData) {
     var countryList = responseData["content"]["states"];
     var stateOptions = new Object();
     for (var i in countryList) {
       stateOptions[countryList[i]["abbreviation"]] = countryList[i]["commonName"];
     }
     Tools.selectOptions({ selectOptions: stateOptions, selector: selectorName, selected: selectorState});
   }
  });

};

function switchPayment(type){
  // Hide/Show selected payment type
  if (type == 'credit'){
    jQuery('div[name=ach]').addClass('hidden');
    jQuery('div[name=credit]').removeClass('hidden');
    jQuery('input[name=pt_card_number]').prop('required',true);
    jQuery('input[name=ach_routing_number]').prop('required',false);
    jQuery('input[name=ach_account_number]').prop('requried',false);
  } else if (type == 'ach'){
    jQuery('div[name=ach]').removeClass('hidden');
    jQuery('div[name=credit]').addClass('hidden');
    jQuery('input[name=pt_card_number]').prop('required',false);
    jQuery('input[name=ach_routing_number]').prop('required',true);
    jQuery('input[name=ach_account_number]').prop('requried',true);
  }
};

function apiMessage(options){
  var messageClass = options['class'];
  var messageText = options['message'];
  var spanName = options['span'];

  var message = jQuery('div.overlayTemplate').clone().removeClass('hidden').addClass('overlay');
  jQuery(message).find('div.infoDiv').addClass(messageClass).removeClass('infoDiv');
  jQuery(message).find('span[name=message_text]').text(messageText);
  jQuery('span[name=' + spanName + ']').prepend(message);
  
};

function drawTable(tableInfo) {
  var cols = tableInfo['columns'];
  var data = new google.visualization.DataTable();
  for (var i = 0; i < cols.length; i++) {
    var currentCol = cols[i];
    data.addColumn(currentCol['type'],currentCol['name']);
  }

  data.addRows(tableInfo['tableData']);

  var table = new google.visualization.Table(document.getElementById('buyRatesContainer'));
  table.draw(data, {showRowNumber: false, width:'100%'});
};
