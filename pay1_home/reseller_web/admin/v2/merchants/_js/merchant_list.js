/* page globals */

var spinnerOptions = {
  lines: 13,      // The number of lines to draw
  length: 5,     // The length of each line
  width: 3,       // The line thickness
  radius: 5,     // The radius of the inner circle
  scale: 1,       // Scales overall size of the spinner
  corners: 1,     // Corner roundness (0..1)
  rotate: 0,      // The rotation offset
  direction: 1,   // 1: clockwise, -1: counterclockwise
  color: '#000',  // #rgb or #rrggbb or array of colors
  speed: 1,       // Rounds per second
  trail: 60,      // Afterglow percentage
  shadow: false,  // Whether to render a shadow
  hwaccel: false,       // Whether to use hardware acceleration
  className: 'spinner', // The CSS class to assign to the spinner
  zIndex: 2e9,    // The z-index (defaults to 2000000000)
  top: '0',     // Top position relative to parent
  left: '0'     // Left position relative to parent
};


var MerchantList = new function() {
  var self = this;
  var reseller;
  var currentCount = 0;

  var currentPage = 0;
  var pageLength = 24;
  var requestPage = 0;
  var requestBatchSize = 250;
  var newMerchantDataSet = true;

  var columnID = '';
  var filter = '';
  var modifier = '';

  var merchantListDataSource;

  self.init = function() {
    /* load the first batch of merchants */
    (function() {
      var options = {
        'pageLength': requestBatchSize,
        'page': requestPage
      }

      var jsonOptions = new Object();
      jsonOptions['key'] = 'merchantlist';
      jsonOptions['action'] = 'read';
      jsonOptions['url'] = '/admin/api/reseller/merchant';
      jsonOptions['options'] = options;
      jsonOptions['onSuccess'] = function(data) {
        requestPage++;
        self.merchantListLoadSuccess(data,options);
        var spinner = new Spinner(spinnerOptions).spin();
        $('#spinner').append(spinner.el);
      }
      Tools.json(jsonOptions);
    }());

    /* set up bindings */
    jQuery('document').ready(function() {
      jQuery('select[name=listPageSelect]').on('change', function() {
        currentPage = jQuery(this).val();
        self.filterMerchants();
      });

      jQuery('#listNavigation input[name=listPageBack]').on('click',function() {
        var sel = jQuery('select[name=listPageSelect]');
        var newVal = parseInt(sel.val(),10) - 1;
        if (newVal < 0) {
          return;
        }
        sel.val(newVal).change();
      });

      jQuery('#listNavigation input[name=listPageNext]').on('click',function() {
        var sel = jQuery('select[name=listPageSelect]');
        var maxVal = sel.find('option:last').val();
        var newVal = parseInt(sel.val(),10) + 1;
        if (newVal > maxVal) {
          return;
        }
        sel.val(newVal).change();
      });

      jQuery('#merchantFilter select').change(function() {
        self.filterMerchants();
      });

      jQuery('#merchantFilter input[name=filter]').on('change keyup',function() {
        if (typeof(filterTimer) != 'undefined') {
          clearTimeout(filterTimer);
        }
        filterTimer = setTimeout(function() {
          currentPage = 0;
          self.filterMerchants();
        },200);
      });
    });
  }

  self.startLoadingMerchants = function(options) {
    if (typeof(options) == 'undefined') {
      options = new Object();
    }

    jQuery('#spinner').fadeIn();

    requestPage = 0;
    currentPage = 0;
    newMerchantDataSet = true;

    self.loadMerchants(options);
  }

  self.loadMerchants = function(options) {
    options['page'] = requestPage;
    options['pageLength'] = requestBatchSize;

    var url;
    if (typeof(reseller) == 'undefined' || reseller == '') {
      url = '/admin/api/reseller/merchant';
    } else {
      url = '/admin/api/reseller/:' + reseller + '/merchant';
    }

    var jsonOptions = new Object();
    jsonOptions['key'] = 'merchantlist';
    jsonOptions['action'] = 'read';
    jsonOptions['url'] = url;
    jsonOptions['options'] = options;
    jsonOptions['onSuccess'] = function(data) {
      requestPage++;
      self.merchantListLoadSuccess(data,options);
    }
    jsonOptions['onError'] = function() {
      alert('Something went wrong...please try again.  If the error continues to occur, please contact support.  This page will now be reloaded.');
      window.location.reload();
    }
    Tools.json(jsonOptions);
  }


  self.addSubresellerSelector = function(subresellerJSONResponse,isSubreseller) {
    var subresellerInfo = subresellerJSONResponse['content']['subresellerInfo'];

    if (subresellerInfo.length == 0) {
      return;
    }

    var template = jQuery('ul.resellerSelectors li.resellerSelectorTemplate').clone();
    template.removeClass('resellerSelectorTemplate').removeClass('rt-hidden');
    var theSelect = template.find('select');

    if (!isSubreseller) {
      template.find('span.deleteResellerFilter').addClass('rt-hidden');
    } else {
      template.find('span.deleteResellerFilter').click(function() {
        template.nextAll().remove().promise().done(function() {
          template.remove().promise().done(function() {
            jQuery("#merchantList ul.resellerSelectors li:last select").val(
              jQuery("#merchantList ul.resellerSelectors li:last option:first").val()
            );
            self.updateForReseller();
          });
        });
      });
      template.find('input[name=parent]').val(
        jQuery("#merchantList ul.resellerSelectors li:last select").val()
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

    jQuery('#merchantList ul.resellerSelectors').append(template);

    self.sortSubResellerSelector(theSelect);
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
    theSelect.find('option[value="none"]').prependTo(theSelect).prop("selected", true);
  }

  self.updateForReseller = function() {
    var account = jQuery("#merchantList ul.resellerSelectors li:last select").val()
    reseller = account;
    var url;

    if (reseller == 'none') {
      reseller = jQuery("#merchantList ul.resellerSelectors li:last input[name=parent]").val();
    }
    url = '/admin/api/reseller/:' + reseller + '/subreseller';

    if (reseller != jQuery("#merchantList ul.resellerSelectors li:last input[name=parent]").val()) {
      Tools.json({
        'url': url,
        'action': 'read',
        'onSuccess': function(data) {
          self.addSubresellerSelector(data, true);
        },
        'key': 'subreseller'
      });
    }

    if (reseller) {
      self.startLoadingMerchants({ 'reseller': reseller });
    } else {
      self.startLoadingMerchants();
    };
  }

  self.merchantListLoadSuccess = function(data, options) {
    if (typeof(data['content']) == undefined) {
      return;
    }

    var count = data['content']['count'];

    if (requestPage * requestBatchSize < count) {
      self.loadMerchants(options);
    } else {
      jQuery('#spinner').fadeOut();
    }

    var list = data['content']['merchantList'];
    self.merchantsLoaded(list);
  }


  self.merchantsLoaded = function(data) {
    if (typeof(merchantListDataSource) == 'undefined' || newMerchantDataSet) {
      merchantListDataSource = new ChartDataSource();

      merchantListDataSource.addColumn({'name':'Username','type':'string','id':'username'});
      merchantListDataSource.addColumn({'name':'Company Name','type':'string','id':'company'});
      merchantListDataSource.addColumn({'name':'Status','type':'string','id':'status'});
      merchantListDataSource.addColumn({'name':'Start Date','type':'string','id':'startDate'});

      merchantListDataSource.setPageSize(pageLength);
    }

    newMerchantDataSet = false;

    for (var i in data) {
      var username    = data[i]['merchant'];
      var company     = data[i]['name'];
      var status      = data[i]['status'];
      var startDate   = data[i]['startDate'];
      merchantListDataSource.addRow([username,company,status,startDate]);
    }

    self.filterMerchants();
  }

  self.filterMerchants = function() {
    var columnID = jQuery('#merchantFilter select[name=columnID]').val();
    var modifier = jQuery('#merchantFilter select[name=modifier]').val();
    var filter   = jQuery('#merchantFilter input[name=filter]').val();

    if (modifier == 'starts') {
      filter = '^' + filter;
    } else if (modifier == 'ends') {
      filter = filter + '$';
    }

    var filteredMerchantList = merchantListDataSource.filter([{'columnID': columnID,'filter': filter}]);

    self.drawMerchantTable(filteredMerchantList.getPage(currentPage));
    self.merchantCount(filteredMerchantList.rows().length);
  }

  self.merchantCount = function(count) {
    // if the count is the same as the current count, do nothing.
    if (count == currentCount) {
      return;
    }
    currentCount = count;

    var numberOfPages = Math.ceil(count/pageLength);

    var aSelect = jQuery('<select>');
    for (var i = 0; i < numberOfPages; i++) {
      var selectOption = jQuery('<option>');
      selectOption.attr('value',i);
      selectOption.html(i+1);
      aSelect.append(selectOption);
    }
    jQuery('#listNavigation select[name=listPageSelect]').html(aSelect.html());

    self.pageInfo(parseInt(currentPage), parseInt(count));
  }

  self.pageInfo = function(page, count) {
    var min = (parseInt(page) * pageLength) + 1;
    var max = (parseInt(page) + 1) * pageLength;

    if (max > count) {
      max = count;
    }

    var str = '';
    if (max == 0) {
      str = 'No Results.';
    } else {
      str = min + '-' + max + ' of ' + count;
    }

    jQuery('#page-info span').text(str);
  }


  self.drawMerchantTable = function(data) {
    var options = {
      sortColumn: data.getSortColumnIndex(),
      sortAscending: (data.getSortOrder() == 'ascending'),
      sort: 'event'
    };

    var c = new Chart();
    c.setContainerID('merchantTable');
    c.setAPISpecificOptions(options);

    c.setDrawFunction(function(table, d, options) {
      table.draw(d, options);

      google.visualization.events.addListener(table, 'sort', function(event) {
        if (event['ascending']) {
          merchantListDataSource.setSortOrder('ascending');
        } else {
          merchantListDataSource.setSortOrder('descending');
        }

        merchantListDataSource.setSortColumnIndex(event['column']);
        merchantListDataSource.sort();
        self.filterMerchants();
      });

      google.visualization.events.addListener(table, 'select', function() {
        var s = table.getSelection();
        var row = s[0].row;
        var str = d.getFormattedValue(row, 0);
        jQuery('#merchantList form #merchant').val(str);
        jQuery('#merchantList form').submit();
      });
    });

    c.drawTable(data);
  }
}
