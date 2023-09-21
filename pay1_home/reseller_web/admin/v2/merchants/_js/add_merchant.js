
var AddMerchant = new function() {
  var self = this;
  var processorInfo = new Object();
  var _timer;
  var lastNameChecked = "";
  var _companyNameTimer;

  self.generateUsername = function(companyName) {
    var usernamePrefix = companyName.replace(/\W/g,'').substring(0,9);
    var rand = ((Math.random()) + "").substring(2,5)
    jQuery('input[name=merchantAccountName]').val(usernamePrefix+rand).change();
  }

  self.companyNameInputChanged = function() {
    var value = jQuery('input[name=companyName]').val();
    var current = jQuery('input[name=merchantAccountName]').val();
    if (value.length >= 3 && current === "") {
      if (typeof(_companyNameTimer) != 'undefined') {
        clearTimeout(_companyNameTimer);
      }
      _companyNameTimer = window.setTimeout(function () {
        self.generateUsername(value);
      }, 5);
    }
  }

  self.usernameAvailable = function(username) {
    if (self.lastNameChecked != username) {
      self.lastNameChecked = username;
      jQuery('#merchantNameError i.fa').remove();
      jQuery('#merchantNameError').prepend('<i class="fa fa-search"></i>');
      jQuery('#merchantNameError').removeClass().find('span').text('Checking Username Availability');
      if (username.length >= 6 && username.length <= 12){
        self._checkName(username);
      } else {
        window.clearTimeout(_timer);
        jQuery('input[name=addMerchantButton]').prop('disabled',true);

        var text = "Account name must be between 6 and 12 characters";
        jQuery('#merchantNameError span').text(text);
        jQuery('#merchantNameError i.fa').remove();
        jQuery('#merchantNameError').addClass('error');
      }
    }
  }

  self._checkName = function(username) {
      window.clearTimeout(_timer);
      _timer = window.setTimeout(function() {
        Tools.json({ url: '/admin/api/username/:' + username,
          method: 'GET',
          key:'username',
          callback: function(content) {
            var exists = content['content']['exists'];

            if ( exists == "true") {
              jQuery('input[name=addMerchantButton]').prop('disabled',true);

              var text = "Account name already exists";
              jQuery('#merchantNameError span').text(text)
              jQuery('#merchantNameError i.fa').remove();
              jQuery('#merchantNameError').removeClass('success').addClass('error').prepend('<i class="fa fa-times-circle"></i>');
            } else {
              jQuery('#merchantNameError i.fa').remove();
              jQuery('#merchantNameError').removeClass('error').addClass('success').prepend('<i class="fa fa-check-circle-o"></i>');
              jQuery('#merchantNameError span').text('Available');
              jQuery('input[name=addMerchantButton]').prop('disabled',false);
            }

          }
        });
      },500);
  };

  self.init = function() {
    jQuery('document').ready(function() {
      // link the state and country selects
      Tools.linkStateSelectorToCountrySelector({'countrySelector':'select[name=companyCountry]', 'stateSelector':'select[name=companyStateProvince]'});

      jQuery('div.processor select.processorSelector').on('change',function() {
        var theSelect = this;
        var selectedProcessor = jQuery(this).val();
        if (selectedProcessor != '') {
          Tools.json({
            'url': '/admin/api/processor/:' + selectedProcessor,
            'method': 'GET',
            'callback': function(data) {
                if (typeof(data['content']) != 'undefined' && typeof(data['content']['processor'] != 'undefined')) {
                  self.showProcessorFields(theSelect,data['content']['processor']);
                  processorInfo[selectedProcessor] = data['content']['processor'];
                }
              }
          });
        } else {
          jQuery(theSelect).closest('div.processor').find('label.insert').remove()
        }
      })

      jQuery('#merchantGatewayAccount input[name=merchantAccountName]').on('keyup change paste', function() {
        AddMerchant.usernameAvailable(jQuery(this).val());
      });

      jQuery('input[name=addMerchantButton]').click(function () {
        jQuery('input[name=addMerchantButton]').prop('disabled', true);
        AddMerchant.add();
      });

      jQuery('input[name=companyName]').change(function() {
        self.companyNameInputChanged();
      });
    });
  }

  self.showProcessorFields = function (aSelect,data) {
    function getSettingByID(processor,id) {
      var settings = processorInfo[processor]['settings'];
      for (var i = 0; i < settings.length; i++) {
        if (settings[i]['id'] == id) {
          return settings[i];
        }
      }
    }

    function createSetting(processor,settingID,parentID) {
      var setting = getSettingByID(processor,settingID);
      var settingName = setting['settingName'];
      var displayName = setting['displayName'];
      var options     = setting['options'];
      // if there are no options, the input type is input
      var settingTemplate;

      var type = 'input';
      var settingField;

      if (typeof(options) == 'object' && options.length > 0) {
        settingTemplate = jQuery('div.processor.template label.select').clone();
        settingField = settingTemplate.find('select');
        type = 'select';
      } else {
        settingTemplate = jQuery('div.processor.template label.input').clone();
        settingField = settingTemplate.find('input');
      }

      settingTemplate.attr('for',settingName);
      settingTemplate.find('span').html(displayName);
      settingTemplate.data('parentID',parentID);

      settingField.attr('name',settingName)
      settingField.data('settingID',setting['id']);

      if (type == 'select') {
        // add options to the select
        if (setting['multipleOptions'] == 1) {
          settingField.prop('multiple',true);
        }
        for (var i = 0; i < options.length; i++){
          var currentOpt = options[i];
          var optionHTML = jQuery('<option>');
          optionHTML.val(currentOpt['option']).text(currentOpt['display']);
          optionHTML.data('settingID',setting['id']);
          optionHTML.data('subsettings',currentOpt['subsettings']);
          settingField.append(optionHTML);
        }

        // add binding to add subsettings based on selected option
        settingField.on('change',function() {
          var selected = settingField.find('option:selected');
          var subsettings = selected.data('subsettings');
          var settingID = setting['id'];//settingField.data('settingID');
          settingTemplate.siblings().each(function(k,v) {
            if (jQuery(v).data('parentID') == settingID) {
              jQuery(v).remove();
            }
          }).promise().done(function() {
            if (typeof subsettings == 'object') {
              for (var i = 0; i < subsettings.length; i++) {
                settingTemplate.after(createSetting(processor,subsettings[i],settingID));
              }
            }
          });
        });
      }

      return settingTemplate;
    }

    processorInfo[data['shortName']] = data;
    var processorBox = jQuery(aSelect).closest('div.processor');
    processorBox.find('label.insert').remove().promise().done(function() {
      for (var i in data['settings']) {
        if (data['settings'][i]['required'] == 1) {
          processorBox.append(createSetting(data['shortName'],data['settings'][i]['id']));
        }
      }
    })

  }

  self.add = function() {
    jQuery('input[name=addMerchantButton]').prop('disabled', true);
    var ProcessorList = [];

    var subresellerSelector = jQuery('#merchantAdd select.reseller-input-control:last-child');
    var subreseller = '';
    if (typeof(subresellerSelector) !== 'undefined') {
      subreseller = subresellerSelector.val();
      console.log('subreseller is ',subreseller);
      if (subreseller == null || typeof(subreseller) === 'undefined') {
        alert('Please select a subreseller.');
        jQuery('input[name=addMerchantButton]').prop('disabled',false);
        jQuery('#blurWrapper').removeClass('blur');
        jQuery('#blockInteraction').css('display','none');
        return
      } else if (subreseller == 'none') {
        subreseller = '';
      } else {
        subreseller = ':' + subreseller;
      }
    }

    function i(field) {
      return jQuery('input[name=' + field + ']').val();
    }

    function s(field) {
      return jQuery('select[name=' + field + ']').val();
    }

    function processorSettings(processorType) {
      var processor = {
          "shortName": s(processorType),
          "setting": []
      };

      jQuery('select[name=' + processorType + ']').parent().siblings('label').each(function() {
        if (jQuery(this).find('select').val() != null ) {
          processor['setting'].push( { "name": jQuery(this).find('select').attr('name'), "value": jQuery(this).find('select').val() } );
        } else {
          processor['setting'].push( { "name": jQuery(this).find('input').attr('name'), "value": jQuery(this).find('input').val() } );
        }
      });

      return processor;
    }

    jQuery('#blurWrapper').addClass('blur');
    jQuery('#blockInteraction').css('display','block');

    var JSONData = {
      "account": {
        "processors": {
          "cardProcessor": s('cardProcessor'),
          "achProcessor": s('achProcessor'),
          "tdsProcessor": s('tdsProcessor'),
          "walletProcessor": s('walletProcessor'),
          "emvProcessor": s('emvProcessor'),
          "processor": []
        },
        "primaryContact": {
          "emailList": [
            {
              "primary": "true",
              "type": "primary",
              "address": i('companyEmail')
            }
          ],
          "addressList": [
            {
              "primary": "true",
              "type": "primary",
              "streetLine1": i('companyAddress1'),
              "streetLine2": i('companyAddress2'),
              "city": i('companyCity'),
              "stateProvince": s('companyStateProvince'),
              "postalCode": i('companyPostalCode'),
              "country": s('companyCountry')
            }
          ],
          "phoneList": [
            {
              "primary": "true",
              "type":"phone",
              "number": i('companyPhone')
            },
            {
              "primary": "true",
              "type": "fax",
              "number": i('companyFax')
            }
          ],
          "name": i('primaryContactName')
        },
        "billing": {
          "contact": {
            "emailList": [
              {
                "primary": "true",
                "type": "primary",
                "address": i('billingContactEmail')
              }
            ]
          }
        },
        "technicalContact": {
          "emailList": [
            {
              "primary": "true",
              "type": "primary",
              "address": i('technicalContactEmail')
            }
          ],
          "phoneList": [
            {
              "primary": "true",
              "type": "phone",
              "number": i('technicalContactPhone')
            }
          ],
          "name": i('technicalContactName')
        },
        "gatewayAccountName": i('merchantAccountName'),
        "companyName": i('companyName'),
        "url": i('companyURL')
      }
    };

    //Assemble Processor Settings Array
    if ( s('cardProcessor') != "" ){
      var cardProc = processorSettings('cardProcessor');
      JSONData['account']['processors']['processor'].push(cardProc);
    }

    if ( s('achProcessor') != "" ){
      var achProc = processorSettings('achProcessor');
      JSONData['account']['processors']['processor'].push(achProc);
    }

    if ( s('tdsProcessor') != "" ){
      var tdsProc = processorSettings('tdsProcessor');
      JSONData['account']['processors']['processor'].push(tdsProc);
    }

    if ( s('walletProcessor') != "" ){
      var walletProc = processorSettings('walletProcessor');
      JSONData['account']['processors']['processor'].push(walletProc);
    }

    if ( s('emvProcessor') != "" ){
      var emvProc = processorSettings('emvProcessor');
      JSONData['account']['processors']['processor'].push(emvProc);
    }

    var postUrl = '/admin/api/reseller/merchant';
    if (subreseller !== '') {
      postUrl = '/admin/api/reseller/' + subreseller + '/merchant';
    }

    Tools.json({ url: postUrl,
      action: 'create',
      data: JSONData,
      onSuccess: function (content) {
        var data = content['content'];
        var popup = jQuery('div.overlayTemplate').clone().removeClass('overlayTemplate').toggleClass('rt-hidden').addClass('overlay');
        jQuery(popup).find('input[name=newAccountName]').val(data['account']['gatewayAccountName']);

        jQuery(popup).find('h1').text("Account " + data['account']['gatewayAccountName'] + " has been created");
        jQuery('#merchantAdd').prepend(popup);
        jQuery('input[name=addMerchantButton]').prop('disabled', false);
      },
      onError: function(error) {
        alert('Something went wrong...please try again.  If the error continues to occur, contact support.');
        jQuery('input[name=addMerchantButton]').prop('disabled',false);
        jQuery('#blurWrapper').removeClass('blur');
        jQuery('#blockInteraction').css('display','none');
       }
    });
  }

  self.addSubresellerSelector = function(subresellerJSONResponse,isSubreseller) {
    var subresellerInfo = subresellerJSONResponse['content']['subresellerInfo'];

    if (subresellerInfo.length == 0) {
      return;
    }

    var template = jQuery('#merchantList ul.resellerSelectors li.resellerSelectorTemplate').clone();
    template.removeClass('resellerSelectorTemplate').removeClass('rt-hidden');
    var theSelect = template.find('select');

    if (!isSubreseller) {
      template.find('span.deleteResellerFilter').addClass('rt-hidden');
    } else {
      template.find('span.deleteResellerFilter').click(function() {
        template.nextAll().remove().promise().done(function() {
          template.remove().promise().done(function() {
            jQuery("#merchantAdd ul.resellerSelectors li:last select").val(
              jQuery("#merchantAdd ul.resellerSelectors li:last option:first").val()
            );
            self.updateForReseller();
          });
        });
      });
      template.find('input[name=parent]').val(
        jQuery("#merchantAdd ul.resellerSelectors li:last select").val()
      );
    }

    for (i = 0; i < subresellerInfo.length; i++) {
      var option = jQuery('<option>');
      option.attr('value',subresellerInfo[i]['username']);
      option.html(subresellerInfo[i]['company']);
      theSelect.append(option);
    }

    theSelect.change(function() {
      template.nextAll().remove().promise().done(function() {
        self.updateForReseller();
      });
    });

    jQuery('#merchantAdd ul.resellerSelectors').append(template);

    self.sortSubResellerSelector(theSelect);
    theSelect.prepend('<option disabled selected>Select Subreseller</option>');
  }

  self.updateForReseller = function() {
    var account = jQuery("#resellerSelectors li:last select").val()
    reseller = account;
    var url;

    if (reseller == 'none') {
      reseller = jQuery("#resellerSelectors li:last input[name=parent]").val();
    }
    url = '/admin/api/reseller/:' + reseller + '/subreseller';

    if (reseller != jQuery("#resellerSelectors li:last input[name=parent]").val()) {
      Tools.json({
        'url': url,
        'action': 'read',
        'callback': function(data) {
          self.addSubresellerSelector(data, true);
        },
        'key': 'subreseller'
      });
    }
  }

  self.sortSubResellerSelector = function(theSelect) {
    // sort by text
    selectOptionText = theSelect.find('option');
    selectOptionText.sort(function(a,b) {
      a = a.text.toLowerCase();
      b = b.text.toLowerCase();
      return ((a < b) ? -1 : ((a > b) ? 1 : 0));
    });
    theSelect.empty().append(selectOptionText);
    theSelect.find('option[value="none"]').prependTo(theSelect);//.prop("selected", true);
  }
};
