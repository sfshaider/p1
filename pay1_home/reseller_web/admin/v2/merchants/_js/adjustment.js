var Adjustment = new function() {
  var self = this;
  var _coaDialog;
  var _coaAccountCreated = false;
  var _mcc;
  var _achFee;
  var _buckets = {};
  var _caps = {};
  var valid = 'false';

  self.openCOADialog = function() {
    _coaDialog.dialog('open');
    _coaDialog.dialog('widget').parent().find(".ui-widget-overlay").css("background", "#666");
  }

  self.closeCOADialog = function() {
    _coaDialog.dialog('close');
  }

  self.openBucketDialog = function() {
    _bucketDialog.dialog('open');
    _bucketDialog.dialog('widget').parent().find(".ui-widget-overlay").css("background", "#666");
  }

  self.closeBucketDialog = function() {
    _bucketDialog.dialog('close');
  }

  self.openCapDialog = function() {
    _capDialog.dialog('open');
    _capDialog.dialog('widget').parent().find(".ui-widget-overlay").css("background", "#666");
  }

  self.closeCapDialog = function() {
    _capDialog.dialog('close');
  }

  self.init = function() {
    jQuery('document').ready(function() {
      _coaDialog = jQuery("#createCOAAccountDialog").dialog({
        autoOpen: false,
        height: 300,
        width: 350,
        modal: true,
        buttons: {
          "Create COA account": function() {
            self.createCOAAccount();
          },
          "Cancel": function() {
            self.closeCOADialog();
          }
        },
        close: function() {
          coaAccountCreationForm[0].reset();
        }
      });

      _bucketDialog = jQuery("#createBucketDialog").dialog({
        autoOpen: false,
        height: 520,
        width: 350,
        modal: true,
        buttons: {
          "Create Bucket": function() {
            var form = jQuery(this).find('form');
            var paymentVehicleID   = form.find('select[name=paymentVehicleID]').val()
            var paymentVehicleText = form.find('select[name=paymentVehicleID] option:selected').html()
            var base = form.find('input[name=base]').val()
            var totalRate = form.find('input[name=totalRate]').val();
            var fixedAdjustment = form.find('input[name=fixedAdjustment]').val();
            var coaRate = form.find('input[name=coaRate]').val();
            self.createBucket(paymentVehicleID,paymentVehicleText,base,totalRate,fixedAdjustment,coaRate);
            self.closeBucketDialog();
          },
          "Cancel": function() {
            self.closeBucketDialog();
          }
        },
        close: function() {
          bucketCreationForm[0].reset();
        }
      });

      _capDialog = jQuery("#createCapDialog").dialog({
        autoOpen: false,
        height: 350,
        width: 350,
        modal: true,
        buttons: {
          "Create Cap": function() {
            var form = jQuery(this).find('form');
            var paymentVehicleID   = form.find('select[name=paymentVehicleID]').val()
            var paymentVehicleText = form.find('select[name=paymentVehicleID] option:selected').html()
            var percent = parseFloat(form.find('input[name=percentCap]').val(),10)
            var fixed   = parseFloat(form.find('input[name=fixedCap]').val(),10)
            self.createCap(paymentVehicleID,paymentVehicleText,percent,fixed);
            self.closeCapDialog();
          },
          "Cancel": function() {
            self.closeCapDialog();
          }
        },
        close: function() {
          capCreationForm[0].reset();
        }
      });

      var coaAccountCreationForm = _coaDialog.find("form").on("submit", function(event) {
        event.preventDefault();
      });

      var bucketCreationForm = _bucketDialog.find("form").on("submit", function(event) {
        event.preventDefault();
      });

      var capCreationForm = _capDialog.find("form").on("submit", function(event) {
        event.preventDefault();
      });

      jQuery('#createCOAAccountButton').on('click',function() {
        self.openCOADialog();
      });

      jQuery('#updateCOAAccountButton').on('click',function() {
        self.updateCOAAccount();
      });

      jQuery('#createBucketButton').on('click',function() {
        self.openBucketDialog();
      });

      jQuery('#createCapButton').on('click',function() {
        self.openCapDialog();
      });

      jQuery('#adjustmentSettings select[name=enabled]').on('change',function() {
        self.enabledChanged();
      }).change();

      jQuery('#adjustmentSettings select[name=model]').on('change',function() {
        self.modelChanged();
      }).change();

      jQuery('#adjustmentSettings select[name=model]').on('change',function() {
        self.setCustomerOverride();
      });  // does not trigger change on page load

      jQuery('#adjustmentSettings select[name=customerOverride]').on('change',function() {
        self.setOverrideCheckboxIsChecked();
      }).change();

      jQuery('#adjustmentSubmit').on('click',function() {
        self.saveAdjustmentSettings();
      });

      Tools.createSpinner('coaSettings','#coaSettingsSpinner');

      self.checkCOAAccountStatus();
    });
  }


  /* Begin COA Settings methods */
  self.createCOAAccount = function() {
    var mcc = jQuery('#createCOAAccountDialog input[name=mcc]').val();
    self.verifyMCC(mcc,self._createCOAAccount);
    jQuery('#createCOAAccountDialog input[name=mcc]').removeClass('badMCC');
  }

  self._createCOAAccount = function() {
    if (self.valid) {
    var achFee = jQuery('#createCOAAccountDialog input[name=achFee]').val();
    var merchant = jQuery('#createCOAAccountDialog input[name=gatewayAccount]').val();
    var data = { 'achFee': achFee };

    Tools.json({ 'url':'/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account',
        'action': 'create',
           'key': 'coaAccount',
          'data': data,
      'callback': function(responseData) {
                    try {
                      self.setACHFee(responseData['content']['account']['achFee']);
                      self.createCOAMerchantAccount();
                    } catch (e) {
                      self.closeCOADialog();
                    }
                  }});
    } else {
       jQuery('#createCOAAccountDialog input[name=mcc]').addClass('badMCC').focus();
    }
  }

  self.createCOAMerchantAccount = function() {
    var mcc = jQuery('#createCOAAccountDialog input[name=mcc]').val();
    var merchant = jQuery('#createCOAAccountDialog input[name=gatewayAccount]').val();

    var data = { 'mcc': mcc };

    Tools.json({ 'url': '/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account/merchant_account',
        'action': 'create',
           'key': 'coaMerchantAccount',
          'data': data,
      'callback': function(responseData) {
                    try {
                      self.setMCC(responseData['content']['merchantAccount']['mcc']);
                      self.setCOAAccountCreated(true,true);
                      self.closeCOADialog();
                    } catch (e) {
                      self.closeCOADialog();
                    }
                  }});
  }

  self.updateCOAAccount = function() {
    var mcc = jQuery('#coaSettings input[name=mcc]').val();
    self.verifyMCC(mcc,self._updateCOAAccount);
    jQuery('#coaSettings input[name=mcc]').removeClass('badMCC');

  }

  self._updateCOAAccount = function() {
    if (self.valid) {

    var achFee = jQuery('#coaSettings input[name=achFee]').val();
    var merchant = jQuery('#coaSettings input[name=gatewayAccount]').val();

    self.showCOASpinner();

    var data = { 'achFee': achFee };

    Tools.json({ 'url':'/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account',
        'action': 'update',
           'key': 'coaAccount',
          'data': data,
      'callback': function(responseData) {
                    try {
                      self.setACHFee(responseData['content']['account']['achFee']);
                      self.updateCOAMerchantAccount();
                    } catch (e) {
                      /* display some error */
                      self.hideCOASpinner();
                    }
                  }});
    } else {
       jQuery('#coaSettings input[name=mcc]').addClass('badMCC').focus();
    }
  }

  self.updateCOAMerchantAccount = function() {
    var mcc = jQuery('#coaSettings input[name=mcc]').val();
    var merchant = jQuery('#coaSettings input[name=gatewayAccount]').val();

    var data = { 'mcc': mcc };

    Tools.json({ 'url': '/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account/merchant_account',
        'action': 'update',
           'key': 'coaMerchantAccount',
          'data': data,
      'callback': function(responseData) {
                    try {
                      self.setMCC(responseData['content']['merchantAccount']['mcc']);
                      Tools.stopSpinner('coaSettings');
                    } catch (e) {
                      /* display some error */
                    } finally {
                      self.hideCOASpinner();
                    }
                  }});
  }

  self.showCOASpinner = function() {
    jQuery('#coaSettingsSpinner').removeClass('rt-hidden');
    Tools.startSpinner('coaSettings');
  }

  self.hideCOASpinner = function() {
    jQuery('#coaSettingsSpinner').addClass('rt-hidden');
    Tools.stopSpinner('coaSettings');
  }

  self.setCOAAccountCreated = function(state,midState) {
    jQuery('document').ready(function() {
      if (state == true) {
        _coaAccountCreated = true;
        self.hideCOASpinner();
        jQuery('#merchantAdjustmentInfo .coaAccountCreated').removeClass('rt-hidden');
        jQuery('#merchantAdjustmentInfo .coaAccountNotCreated').addClass('rt-hidden');
        jQuery('#merchantAdjustmentInfo .badMID').addClass('rt-hidden');
      } else {
        _coaAccountCreated = false;
        self.hideCOASpinner();
        jQuery('#merchantAdjustmentInfo .coaAccountCreated').addClass('rt-hidden');
        if (midState == true){
          jQuery('#merchantAdjustmentInfo .coaAccountNotCreated').removeClass('rt-hidden');
          jQuery('#merchantAdjustmentInfo .badMID').addClass('rt-hidden');
        } else {
          jQuery('#merchantAdjustmentInfo .badMID').removeClass('rt-hidden');
          jQuery('#merchantAdjustmentInfo .coaAccountNotCreated').addClass('rt-hidden');
        }
      }
    });
  }

  self.setMCC = function(mcc) {
    _mcc = mcc;
    jQuery('#coaSettings input[name=mcc]').val(mcc);
  }

  self.setACHFee = function(achFee) {
    _achFee = achFee;
    jQuery('#coaSettings input[name=achFee]').val(achFee);
  }

  self.displayError = function(message) {
    console.error(message);
  }

  self.checkCOAAccountStatus = function() {
    var merchant = jQuery('#createCOAAccountDialog input[name=gatewayAccount]').val();

    self.showCOASpinner();

    Tools.json({ 'url': '/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account',
        'action': 'read',
           'key': 'coaAccount',
      'callback': function(responseData) {
                    try {
                      self.setACHFee(responseData['content']['account']['achFee']);
                      self.checkCOAMerchantAccountStatus();
                    } catch (e) {
                      var midCheck = false;
                      if ( responseData['content']['account']['mid'] == 'true'){
                        midCheck = true ;
                      }
                      self.setCOAAccountCreated(false,midCheck);
                    }
                  },
         'error': function(responseData) {
                    try {
                      var midCheck = false;

                      //responseJSON is added by error response
                      if ( responseData['responseJSON']['content']['data']['mid'] == 'true'){
                        midCheck = true ;
                      }

                      self.setCOAAccountCreated(false,midCheck);
                    } catch (e) {
                      self.displayError('An unknown error occurred.');
                    } finally {
                      self.hideCOASpinner();
                    }
         }
     });
  }

  self.checkCOAMerchantAccountStatus = function() {
    var merchant = jQuery('#createCOAAccountDialog input[name=gatewayAccount]').val();


    Tools.json({ 'url': '/admin/api/reseller/merchant/:' + merchant + '/adjustment/coa/account/merchant_account',
        'action': 'read',
           'key': 'coaAccountMerchantAccount',
      'callback': function(responseData) {
                    try {
                      self.setMCC(responseData['content']['merchantAccount']['mcc']);
                      self.setCOAAccountCreated(true,true);
                    } catch (e) {
                      var midCheck = false;
                      if ( responseData['content']['account']['mid'] == 'true'){
                        midCheck = true ;
                      }
                      self.setCOAAccountCreated(false,midCheck);
                    } finally {
                      self.hideCOASpinner();
                    }
                  },
       'error': function(error) {
                    try {
                      Tools.stopSpinner('coaSettings');
                    } catch (e) {
                      self.displayError('An unknown error occurred.');
                    } finally {
                      jQuery('div.badAccount').removeClass('rt-hidden');
                      self.hideCOASpinner();
                    }

       }});
  }
  /* End COA settings methods */

  /* Begin Adjustment settings methods */
  self.enabledChanged = function() {
    var newValue = jQuery('#adjustmentSettings select[name=enabled]').val();
    if (newValue == 1) {
      jQuery('#adjustmentSettings label[for=model]').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields').removeClass('rt-hidden');
    } else {
      jQuery('#adjustmentSettings label[for=model]').addClass('rt-hidden');
      jQuery('#adjustmentSettingsFields').addClass('rt-hidden');
    }
  }

  self.modelChanged = function() {
    var newValue = jQuery('#adjustmentSettings select[name=model]').val();
    if (newValue == 9 || newValue == 12) { // intelligent rate and convenience fee
      jQuery('#adjustmentSettingsFields label.feeTypeOnly').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeOnly').addClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeDROnly').addClass('rt-hidden');
    } else if (newValue == 7) { // surcharge
      jQuery('#adjustmentSettingsFields label.surchargeOnly').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.feeTypeOnly').addClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeDROnly').addClass('rt-hidden');
    } else if (newValue == 20) { // surcharge-dr
      jQuery('#adjustmentSettingsFields label.surchargeDROnly').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeOnly').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.feeTypeOnly').addClass('rt-hidden');
    } else {
      jQuery('#adjustmentSettingsFields label.feeTypeOnly').addClass('rt-hidden');
      jQuery('#adjustmentModelSettings').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.override').removeClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeOnly').addClass('rt-hidden');
      jQuery('#adjustmentSettingsFields label.surchargeDROnly').addClass('rt-hidden');
    }
  }

  self.setCustomerOverride = function() {
    var modelValue = jQuery('#adjustmentSettings select[name=model]').val();
    var initialOverrideValue = jQuery('select[name=customerOverride]').val();
    if (modelValue == 14) { // optional model
	jQuery('select[name=customerOverride]').val('1').change();
    } else {
	jQuery('select[name=customerOverride]').val('0').change();
    }
    // fade out / in to show user it changed
    if (initialOverrideValue != jQuery('select[name=customerOverride]').val()) {
	jQuery('select[name=customerOverride]').fadeOut('fast').fadeIn('slow');
    }
  }

  self.setOverrideCheckboxIsChecked = function() {
    var customerCanOverride = jQuery('#adjustmentSettings select[name=customerOverride]').val();
    if (customerCanOverride == 1) {
	jQuery('#adjustmentSettingsFields label.overrideCheckbox').removeClass('rt-hidden');
    } else {
        jQuery('#adjustmentSettingsFields label.overrideCheckbox').addClass('rt-hidden');
    }
  }

  self.setBuckets = function(buckets) {
    if (typeof _buckets == 'object') {
      for (var i in buckets) {
        var bucket = buckets[i];
        self.createBucket(bucket['paymentVehicleID'],
         /*           */  bucket['paymentVehicleText'],
         /*  O     O  */  bucket['base'],
         /*     o     */  bucket['totalRate'],
         /*  \_____/  */  bucket['fixedAdjustment'],
         /*      U    */  bucket['coaRate'],
         /*           */  true);
        self.drawBuckets();
      }
    }
  }

  self.createBucket = function(paymentVehicleID,paymentVehicleText,base,totalRate,fixedAdjustment,coaRate,preventDrawing) {
    if (typeof _buckets[paymentVehicleID] == 'undefined') {
      _buckets[paymentVehicleID] = {};
    }
    _buckets[paymentVehicleID][base] = { 'paymentVehicleText': paymentVehicleText,
                                                  'totalRate': totalRate,
                                            'fixedAdjustment': fixedAdjustment,
                                                    'coaRate': coaRate };

    if (typeof(preventDrawing) == 'undefined' || !preventDrawing) {
      self.drawBuckets();
    }
  }

  self.deleteBucket = function(paymentVehicleID,base) {
    if (typeof _buckets[paymentVehicleID] != 'undefined') {
      if (typeof _buckets[base] != 'undefined') {
        delete _buckets[paymentVehicleID][base];
        self.drawBuckets();
      }
    }
  }

  self.drawBuckets = function() {
    jQuery('#adjustmentBuckets div.bucket.added').remove().promise().done(function() {
      var pts = Object.keys(_buckets).sort();
      for (var i in pts) {
        var paymentType = [pts[i]];
        if (typeof _buckets[paymentType] != 'undefined') {
          var bases = Object.keys(_buckets[paymentType]).sort()
          for (var j in bases) {
            var base = bases[j];
            var bucket = _buckets[paymentType][base];

            var template = jQuery('#adjustmentBuckets div.template.bucket').clone().removeClass('template').addClass('added');
            template.find('div.paymentVehicle').html(bucket['paymentVehicleText']);
            template.find('div.base').html(parseFloat(base,10).toFixed(2));
            template.find('div.totalRate').html(parseFloat(bucket['totalRate'],10).toFixed(3));

            template.find('div.fixedAdjustment').html(parseFloat(bucket['fixedAdjustment'],10).toFixed(2));
            template.find('div.coaRate').html(parseFloat(bucket['coaRate'],10).toFixed(3));
            template.find('input[name=base]').val(base);
            template.find('input[name=paymentVehicleID]').val(paymentType);
            template.find('input[type=button]').on('click',function() {
              var bucketRow = jQuery(this).parent().parent();
              var paymentVehicleID = bucketRow.find('input[name=paymentVehicleID]').val();
              var base = bucketRow.find('input[name=base]').val();
              delete _buckets[paymentVehicleID][base];
              bucketRow.remove();
            })
            jQuery('#adjustmentBuckets').append(template);
          }
        }
      }
    });
  }

  self.setCaps = function(caps) {
    if (typeof _caps == 'object') {
      for (var i in caps) {
        var cap = caps[i];
        self.createCap(cap['paymentVehicleID'],
        /*  O     O  */cap['paymentVehicleText'],
        /*     o     */cap['percentCap'],
        /*  \_____/  */cap['fixedCap'],
        /*    U      */true);
        self.drawCaps();
      }
    }
  }

  self.createCap = function(paymentVehicleID,paymentVehicleText,percentCap,fixedCap,preventDrawing) {
    if (typeof _caps[paymentVehicleID] == 'undefined') {
      _caps[paymentVehicleID] = {};
    }
    _caps[paymentVehicleID] = { 'paymentVehicleText': paymentVehicleText,
                                        'percentCap': percentCap,
                                          'fixedCap': fixedCap };
    if (typeof preventDraw == 'undefined' || !preventDrawing) {
      self.drawCaps();
    }
  }

  self.deleteCap = function(paymentVehicleID) {
    if (typeof _caps[paymentVehicleID] != 'undefined') {
      delete _caps[paymentVehicleID];
      self.drawCaps();
    }
  }

  self.drawCaps = function() {
    jQuery('#adjustmentCaps div.cap.added').remove().promise().done(function() {
      var pts = Object.keys(_caps).sort();
      for (var i in pts) {
        var paymentVehicle = [pts[i]];
        if (typeof _caps[paymentVehicle] != 'undefined') {
          var cap = _caps[paymentVehicle];

          var template = jQuery('#adjustmentCaps div.template.cap').clone().removeClass('template').addClass('added');
          template.find('div.paymentVehicle').html(cap['paymentVehicleText']);
          template.find('div.percentCap').html(parseFloat(cap['percentCap'],10).toFixed(2));
          template.find('div.fixedCap').html(parseFloat(cap['fixedCap'],10).toFixed(2));
          template.find('input[name=paymentVehicleID]').val(paymentVehicle);
          template.find('input[type=button]').on('click',function() {
            var capRow = jQuery(this).parent().parent();
            var paymentVehicleID = capRow.find('input[name=paymentVehicleID]').val();
            var base = capRow.find('input[name=base]').val();
            delete _caps[paymentVehicleID];
            capRow.remove();
          })
          jQuery('#adjustmentCaps').append(template);
        }
      }
    });
  }

  self.saveAdjustmentSettings = function() {
    function i(fieldName) {
      return jQuery('#merchantAdjustmentInfo input[name=' + fieldName + ']').val();
    }

    function s(fieldName) {
      return jQuery('#merchantAdjustmentInfo select[name=' + fieldName + ']').val();
    }

    var data = {
      /* general settings */
      enabled: s('enabled'),
      modelID: s('model'),
      customerCanOverride: s('customerOverride'),
      overrideCheckboxIsChecked: s('overrideCheckboxIsChecked'),
      checkCustomerState: s('checkCustomerState'),
      adjustmentIsTaxable: s('adjustmentIsTaxable'),
      processorDiscountRate: i('processorDiscountRate'),

      /* threshold settings */
      threshold: {
        fixed: i('fixedThreshold'),
        percent: i('percentThreshold'),
        modeID: s('thresholdMode')
      },

      /* authorization settings */
      authorization: {
        account: i('feeAccountUsername'),
        typeID: s('authMode'),
        failureModeID: s('failureMode')
      },

      /* buckets */
      buckets: {
        defaultTypeID: s('defaultPaymentVehicleBucket'),
        modeID: s('bucketMode'),
        bucket: [] /* added further down */
      },

      /* caps */
      caps: {
        defaultTypeID: s('defaultPaymentVehicleCap'),
        modeID: s('capMode'),
        cap: [] /* added further down */
      }
    };

    var bucketPaymentVehicleIDs = Object.keys(_buckets);
    for (var i in bucketPaymentVehicleIDs) {
      var paymentVehicleID = bucketPaymentVehicleIDs[i];
      var bases = Object.keys(_buckets[paymentVehicleID]);
      for (var j in bases) {
        var base = bases[j];
        var bucket = {
          'typeID': paymentVehicleID,
          'base': base,
          'coaPercent': _buckets[paymentVehicleID][base]['coaRate'],
          'totalPercent': _buckets[paymentVehicleID][base]['totalRate'],
          'fixedAdjustment': _buckets[paymentVehicleID][base]['fixedAdjustment']
        };

        data['buckets']['bucket'].push(bucket);
      }
    }

    var capPaymentVehicleIDs = Object.keys(_caps);
    for (var i in capPaymentVehicleIDs) {
      var paymentVehicleID = capPaymentVehicleIDs[i];
      var cap = {
        'typeID': paymentVehicleID,
        'fixed': _caps[paymentVehicleID]['fixedCap'],
        'percent': _caps[paymentVehicleID]['percentCap']
      }
      data['caps']['cap'].push(cap);
    }

    var merchant = jQuery('#createCOAAccountDialog input[name=gatewayAccount]').val();
    Tools.json({
           'url': '/admin/api/reseller/merchant/:' + merchant + '/adjustment/',
        'action': 'create',
           'key': 'adjustment',
          'data': data,
      'callback': function(responseData) {
                    alert('Save successful.');
                  }
    });
  }

  self.verifyMCC = function(MCC,callbackFunction) {
    Tools.json ({
            'url': '/admin/api/reseller/merchant/adjustment/coa/account/mcc/:' + MCC,
         'action': 'read',
            'key': 'mcc',
       'callback': function(responseData) {
                     self.valid = responseData["content"]["mcc"] != null;

                     callbackFunction();
                   },
          'error': function(message) {
                     self.valid = false;
                     callbackFunction();
                   }
    });
  }
}

Adjustment.init();
