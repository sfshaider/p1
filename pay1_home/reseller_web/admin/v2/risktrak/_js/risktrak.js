
// var opts is the list of options used to design
// and style the spinner from spin.min.js

var opts = {
  lines: 13, 		// The number of lines to draw
  length: 5, 		// The length of each line
  width: 3, 		// The line thickness
  radius: 5, 		// The radius of the inner circle
  scale: 1, 		// Scales overall size of the spinner
  corners: 1, 		// Corner roundness (0..1)
  rotate: 0, 		// The rotation offset
  direction: 1, 	// 1: clockwise, -1: counterclockwise
  color: '#000',	// #rgb or #rrggbb or array of colors
  speed: 1, 		// Rounds per second
  trail: 60, 		// Afterglow percentage
  shadow: false,	// Whether to render a shadow
  hwaccel: false,	// Whether to use hardware acceleration
  className: 'spinner', // The CSS class to assign to the spinner
  zIndex: 2e9, 		// The z-index (defaults to 2000000000)
  top: '0', 		// Top position relative to parent
  left: '0' 		// Left position relative to parent
};

var merchant = '';

var page = 0;
var pageLength = 500;

function initRisktrak() {		

  $('#exit').click(function() {
    var wrap = $('#order-wrapper');
    wrap.slideUp();
  });

  var spinner = new Spinner(opts).spin();
  $('#spinner').append(spinner.el);
  
  jQuery('#historyFilter input[name=filter]').on('keyup', function() {
		if (typeof(filterTimer) != 'undefined') {
			clearTimeout(filterTimer);
		}
		filterTimer = setTimeout(function() { 
			filterHistory();
		}, 250);
	});

}

function ajaxRisktrak(username) {

  merchant = username;

  // settings

  var url = '/admin/api/reseller/merchant/:' + username + '/risktrak/settings';
  var data = {'merchant': username};

  ajax(url, data, successSettings);

  // transactions

  var url = '/admin/api/reseller/merchant/:' + username + '/risktrak/stats';

  ajax(url, data, successStats);

  // history

  var url = '/admin/api/reseller/merchant/:' + username + '/risktrak/history';
  data['pageLength'] = pageLength;
  data['pageNumer'] = page;

  ajax(url, data, successHistory);

  jQuery('#spinner').fadeIn();
}

function successSettings(data) {

  if (typeof(data['content']) == undefined) {
    return;
  }

  var settings = data['content']['settingsInfo'];

  var str = '(no limit)';
  var email 		= (settings['email'] && settings['email']!=''			? settings['email'] 		: '(no email)');
  var auth_ovr 		= (settings['auth_ovr']	&& settings['auth_ovr']!=''		? settings['auth_ovr'] 		: str);
  var auth_metric 	= (settings['auth_metric'] && settings['auth_metric']!=''	? settings['auth_metric'] 	: str);
  var retn_ovr 		= (settings['retn_ovr']	&& settings['retn_ovr']!=''		? settings['retn_ovr'] 		: str);
  var retn_metric 	= (settings['retn_metric'] && settings['retn_metric']!=''	? settings['retn_metric'] 	: str);
  var ccauth_ovr 	= (settings['ccauth_ovr'] && settings['ccauth_ovr']!=''		? settings['ccauth_ovr'] 	: str);
  var ccauth_metric 	= (settings['ccauth_metric'] && settings['ccauth_metric']!=''	? settings['ccauth_metric'] 	: str);
  var max_auth_vol 	= (settings['max_auth_vol'] && settings['max_auth_vol']!=''	? settings['max_auth_vol'] 	: str);
  var ccretn_ovr 	= (settings['ccretn_ovr'] && settings['ccretn_ovr']!=''		? settings['ccretn_ovr'] 	: str);
  var ccretn_metric 	= (settings['ccretn_metric'] && settings['ccretn_metric']!=''	? settings['ccretn_metric'] 	: str);
  var max_retn_vol 	= (settings['max_retn_vol'] && settings['max_retn_vol']!=''	? settings['max_retn_vol'] 	: str);

  var div = $('#settings');
  div.find('#email').html(email);
  div.find('#suspend-sales-x').html(auth_ovr);
  div.find('#suspend-sales-y').html(auth_metric);
  div.find('#suspend-return-x').html(retn_ovr);
  div.find('#suspend-return-y').html(retn_metric);
  div.find('#freeze-sales-x').html(ccauth_ovr);
  div.find('#freeze-sales-y').html(ccauth_metric);
  div.find('#freeze-sales-z').html(max_auth_vol);
  div.find('#freeze-return-x').html(ccretn_ovr);
  div.find('#freeze-return-y').html(ccretn_metric);
  div.find('#freeze-return-z').html(max_retn_vol);

}

function successHistory(data) {

  if (typeof(data['content']) == undefined) {
    return;
  }

  historyLoaded(data['content']['history']['list']);
  historyCount(data['content']['history']['count']);
}

function successStats(data) {

  if (typeof(data['content']) == undefined) {
    return;
  }

  var stats = data['content']['statsInfo'];
  google.setOnLoadCallback(drawStatsDashboard(stats));
}

var historyList = '';

function historyLoaded(data) {

  var d = new ChartDataSource();

  d.addColumn({'name':'','type':'number','id':'id'});
  d.addColumn({'name':'OrderID','type':'string','id':'orderid'});
  d.addColumn({'name':'Date','type':'datetime','id':'date'});
  d.addColumn({'name':'IPAddress','type':'string','id':'ipaddress'});
  d.addColumn({'name':'Action','type':'string','id':'action'});
  d.addColumn({'name':'Description','type':'string','id':'description'});
	
  var id = (page * pageLength) + 1;
  for (var row in data) {

    var orderid = data[row]['OID'];
    var dbtime = data[row]['TransTime'];
    var action = data[row]['Action'];
    var description = data[row]['Description'];
    var ipaddress = data[row]['IPAddress'];

    var date = dbtime.substring(0,8);
    var time = dbtime.substring(8,dbtime.length);

    var year = Number(date.substring(0,4));
    var month = Number(date.substring(4,6));
    var day = Number(date.substring(6,8));

    var hours = Number(time.substring(0,2));
    var minutes = Number(time.substring(2,4));
    var seconds = Number(time.substring(4,6));

    // January corresponds to month == 0
    var trueDate = new Date(year, month - 1, day, hours, minutes, seconds);

    d.addRow(
      [id, orderid, trueDate, ipaddress, action, description]
    );
    id++;
  }

  historyList = d;

  drawTable(d);
}

var historyId = '';
var historyCountId = '';

var columnID = '';
var filter = '';
var modifier = '';

function filterHistory() {

  columnID = jQuery('#historyFilter select[name=columnID]').val();
  modifier = jQuery('#historyFilter select[name=modifier]').val();
  filter   = jQuery('#historyFilter input[name=filter]').val();

  var url = '/admin/api/reseller/merchant/:' + merchant + '/risktrak/history';
  //historyId = Date.now();
  var data = {
    'merchant': merchant,
    'modifier': modifier,
    'columnID': columnID,
    'filter': filter,
    'count': 'false'
  }

  jQuery('#spinner').fadeIn();

  ajax(url, data, successHistory, 'history');

  // history count

  data['count'] = 'true';

  jQuery('#button-container').addClass('disable');
  ajax(url, data, successHistoryCount, 'count');
}

function historyCount(count) {


  // make buttons
 
  var numButtons = Math.ceil(count/pageLength);
  var container = jQuery('#button-container');
  jQuery('div.page-button-number').remove();
  for (var i = 1; i <= numButtons; i++) {
    var template = container.find('#button-template').clone();
    template.attr('id','page-' +  i);
    template.attr('data-value', i);
    template.removeClass('hidden');
    template.addClass('page-button-number');
    template.find('span').text(i);
    container.append(template);
  }
 
  // add click listener

  jQuery('.page-button-number').click(function() {

    if (jQuery('#button-container').hasClass('disable')) {
      return;
    }

    var val = jQuery(this).data('value') - 1;

    var url = '/admin/api/risktrak/history';
    //historyId = Date.now();
    var data = {
      'merchant': merchant,
      'modifier': modifier,
      'pageNumber': val,
      'pageLength': pageLength,
      'count': false
    };
    /*  'count': 'false',
      'id': historyId
    };*/
    
    if(columnID && filter) {
      data[columnID] = filter;
    }
    
    jQuery('#spinner').fadeIn();

    ajax(url, data, successHistory, 'history');  

    pageInfo(val, count); 
  });

  page = 0;
  pageInfo(page, count); 
}

function pageInfo(value, count) {

  // page feedback
 
  var min = value * pageLength + 1;
  var max = (value + 1) * pageLength;
  
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
  
  jQuery('#button-container').removeClass('disable');
  jQuery('#button-container #page-' + (page + 1)).removeClass('current');
  jQuery('#button-container #page-' + (value + 1)).addClass('current');
  page = value;
}

var currentOID;

function drawTable(data) {

  var options = {
	pageSize: 500,
  };

  var c = new Chart();
  c.setContainerID('historyTable');
  c.setAPISpecificOptions(options);

  c.setDrawFunction(function(table, data, options) {
    var d = data; 
    table.draw(data, options);

    // If the user selects a row, load an order order summary for the given OID
    google.visualization.events.addListener(table, 'select', function() {

      var selection = table.getSelection();
      var orderid;
      for (var i = 0; i < selection.length; i++) {
        var item = selection[i];
        if (item.row != null && item.column != null) {
          var str = d.getFormattedValue(item.row, item.column);
        } else if (item.row != null) {
          var str = d.getFormattedValue(item.row, 1);
        } else if (item.column != null) {
          var str = d.getFormattedValue(0, item.column);
        }
        orderid = str;
      }

      // orderid sometimes returns undefined, catch it and quit
      // or we don't want to execute ajax if it's the current order
      //if (!orderid || orderid == currentOID) {  return;  }

      currentOID = orderid;

      var url = '/admin/api/reseller/merchant/:' + merchant + '/transaction/:' + orderid;
      var data = {
        'merchant': merchant,
        'OID': orderid
      };

      var wrap = $('#order-wrapper');
      var spin = $('#spinner');

      if (wrap.is(':visible')) {
        wrap.slideUp(function() {
          spin.fadeIn();
        });
      } else {
        spin.fadeIn();
      }

      ajax(url, data, orderSuccess, 'order');
    });
  });
  jQuery('#spinner').fadeOut();
  c.drawTable(data);
}

function orderSuccess(data) {

  if (typeof(data['content']) == undefined) {
    return;
  }

  var content = data['content']['summaryInfo'];

  if (typeof(content) == undefined) {
    orderFail();
    return;
  }

  var oplog = content['oplog'];
  var geo = content['geo'];

  // order may have changed, don't display if it has changed
  if (currentOID != oplog['OID']) {  return;  }

  var div = $('#order-summary');

  for (var row in oplog) {
    div.find('#' + row).text(oplog[row]);
  }

  var str = 'CountryCode';
  div.find('#' + str).text(geo[str]);

  // animate: remove the spinner (fade), reveal the order (slide)
  $('#spinner').fadeOut(function() {
    $('#order-wrapper').slideDown();
  });
 
}

function orderFail() {
  $('#spinner').fadeOut();
}

function drawStatsDashboard(stats) {

  var data = new google.visualization.DataTable();
  data.addColumn('date', 'Date');
  data.addColumn('number', 'Volume');
  data.addColumn('number', 'Count');
  //data.addColumn('number', 'Total Volume');

  //var totalVol = 0;
  for (var row in stats) {
    if (stats[row]['Type'] === 'auth') {
      var strDate = stats[row]['TransDate'];

      var year = Number(strDate.substring(0,4));
      var month = Number(strDate.substring(4,6));
      var day = Number(strDate.substring(6,8));

      var volume = Number(stats[row]['Volume']);
      var count = Number(stats[row]['Count']);

      // To catch floating point errors, toFixed(2) keeps 2 decimal places 
      // but turns it into a string, so Number() is used to cast it back.
      //totalVol = Number((totalVol + volume).toFixed(2));  
      data.addRow([new Date(year, month, day), volume, count]); //, totalVol]);
    }
  }

  var columnsTable = new google.visualization.DataTable();
  columnsTable.addColumn('number','colIndex');
  columnsTable.addColumn('string','colLabel');
  var initState = { selectedValues: [] };

  for (var i = 1; i < data.getNumberOfColumns(); i++) {
    columnsTable.addRow([i, data.getColumnLabel(i)]);
    initState.selectedValues.push(data.getColumnLabel(i));
  }
  
  var columnFilter = new google.visualization.ControlWrapper({
    'controlType':'CategoryFilter',
    'containerId':'date_filter',
    'dataTable': columnsTable,
    'options': {
      'filterColumnLabel': 'colLabel',
      'ui': {
        'label': 'Columns',
        'allowType': false,
        'allowMultiple': true,
        'selectedValuesLayout': 'belowStacked'
      }
    },
    'state': initState
  });

  // Create a line chart for the data
  var chart = new google.visualization.ChartWrapper({
    'chartType': 'LineChart',
    'containerId':'line_chart',
    'dataTable': data,
    'options': {
      'height': 500,
      'width': 900,
      'pointsVisible':true,
      'chart': {
        'title': 'Title',
        'subtitle': 'subtitle'
      },
      'hAxis': {
        'title':'Date'
      },
      'vAxis': {
        'title':''
      }
    }
  });

  function setChartView() {
    var state = columnFilter.getState();
    var row;
    var view = {
      columns: [0]
    };
    for (var i = 0; i < state.selectedValues.length; i++) {
      row = columnsTable.getFilteredRows([{column: 1, value: state.selectedValues[i]}])[0];
      view.columns.push(columnsTable.getValue(row, 0));
    }
    view.columns.sort(function(a, b) {
      return (a - b);
    });
    chart.setView(view);
    chart.draw();
  }

  google.visualization.events.addListener(columnFilter, 'statechange', setChartView);

  setChartView();
  columnFilter.draw();

}

/* Helper methods */

function stringEncode(data) {
  
  var str = '/!';
  for (key in data) {
    str += '/' + key + '/:' + data[key]; 
  }
  str = str.substring(0, 1) + str.substring(1,str.length);
  return str;
}

function ajax(url, data, callback) {
  ajax(url, data, callback, '');
}

function ajax(url, data, callback, key) {

  url += stringEncode(data);

  var options = {};
  options['url'] = url;
  options['method'] = 'GET';
  options['callback'] = callback;
  options['key'] = key;

  Tools.json(options);
}

