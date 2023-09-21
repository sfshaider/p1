var UpdateMerchant = new function() { 
  var self = this;

  this.init = function() {
    jQuery('document').ready(function() {
      // link the country and state select
      Tools.linkStateSelectorToCountrySelector({'countrySelector':'select[name=companyCountry]', 'stateSelector':'select[name=companyStateProvince]'});

      jQuery('#saveButton').click(function() {
        self.update();
     });
    });
  }

  this.update = function() {
    function i(inputName) {
      return jQuery('input[name=' + inputName + ']').val();
    }
    function s(selectName) {
      return jQuery('select[name=' + selectName + ']').val();
    }
  
    // this data structure mirrors the schema to update merchants with the api
    var data = {
      'account': {
        'gatewayAccountName': i('gatewayAccountName'),
        'companyName': i('companyName'),
        'url': i('companyURL'),
        'billing': {
          'contact': {
            'emailList': [
              {
                'primary': 'true',
                'type': 'primary',
                'address': i('billingContactEmail')
              }
            ]
          }
        },
        'primaryContact': {
          'name': i('primaryContactName'),
          'emailList': [
            {
              'primary': 'true',
              'type': 'primary',
              'address': i('companyEmail')
            }
          ],
          'addressList': [
            {
              'primary': 'true',
              'type': 'primary',
              'streetLine1': i('companyAddress1'),
              'streetLine2': i('companyAddress2'),
              'city': i('companyCity'),
              'stateProvince': s('companyStateProvince'),
              'postalCode': i('companyPostalCode'),
              'country': s('companyCountry')
            }
          ],
          'phoneList': [
            {
              'primary': 'true',
              'type': 'phone',
              'number': i('companyPhone')
            },
            {
              'primary': 'false',
              'type': 'fax',
              'number': i('companyFax')
            }
          ]
  
        },
        'technicalContact': {
          'emailList': [
            {
              'primary': 'true',
              'type': 'primary',
              'address': i('technicalContactEmail')
            }
          ],
          'phoneList': [
            {
              'primary': 'true',
              'type': 'phone',
              'number': i('technicalContactPhone')
            }
          ],
          'name': i('technicalContactName')
        }
      }
    }
  
    Tools.json({ url: '/admin/api/reseller/merchant/:' + i('gatewayAccountName'),
        action: 'update',
          data: data,
      callback: function(responseData) { }});
  }
}
  
UpdateMerchant.init();

