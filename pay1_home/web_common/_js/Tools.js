var Tools = new function() {
  var self = this;
  var currentToken = jQuery('meta[name=request-token]').attr('content');
  
  var _requestIDs = {};
  var _spinnerOptions = {
    lines: 13,      // The number of lines to draw
    length: 5,     // The length of each line
    width: 2,       // The line thickness
    radius: 3,     // The radius of the inner circle
    scale: 1,       // Scales overall size of the spinner
    corners: 1,     // Corner roundness (0..1)
    rotate: 0,      // The rotation offset
    direction: 1,   // 1: clockwise, -1: counterclockwise
    color: '#000',  // #rgb or #rrggbb or array of colors
    speed: 1,       // Rounds per second
    trail: 50,      // Afterglow percentage
    shadow: false,  // Whether to render a shadow
    hwaccel: false,       // Whether to use hardware acceleration
    className: 'spinner', // The CSS class to assign to the spinner
    zIndex: 2e9,    // The z-index (defaults to 2000000000)
    top: '0',     // Top position relative to parent
    left: '0'     // Left position relative to parent
  };
  var _spinners = {};
  
  self.json = function(options) {
    // set noQueue to false if it is not defined
    if (typeof options["noQueue"] == 'undefined') {
      options["noQueue"] = false;
    } 

    // convert actions to methods
    if (typeof options["action"] != 'undefined') {
      var actions = {"create":"post",
                       "read":"get",
                     "update":"put",
                     "delete":"delete"};
  
      options["method"] = actions[options["action"].toLowerCase()];
    }

    // if an unsupported method is found, remove it
    var methods = {"post":1,"get":1,"put":1,"delete":1};
    if (methods[options["method"].toLowerCase()] != 1) {
      console.error("Invalid method.");
      return;
    }
  
    // encode options into the url
    var requestOptionsString = '/!';
    if (typeof options["options"] == "object") {
      for (requestOption in options["options"]) {
        requestOptionsString += '/' + requestOption + '/:' + options["options"][requestOption];
      }
      if (requestOptionsString != '/!') {
        options["url"] += requestOptionsString;
      }
    }
  
    var requestToken = jQuery('meta[name=request-token]').attr('content');
  
    var key = options['key'];
    if (key) {
      _requestIDs[key] = Date.now();       
    }

    var headers = {
        'X-Gateway-Request-Token': requestToken,
        'Request-ID': _requestIDs[key],
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': 0
    };

    // allows headers to be added as options
    if (typeof options["headers"] == "object") {
      for (i in options["headers"]) {
        headers[i] = options["headers"][i];
      }
    }

    var ajaxOptions = {
      "url" : options["url"],
      "type": options["method"],
      "dataType":"json",
      "headers": headers, 
      "data": JSON.stringify(options["data"]),
      "success": function(responseData) { 
        function doIt() {
          if (!key || _requestIDs[key] == responseData['id']) {
            var rawData = { 'content': responseData['content']['data'] };
            if (typeof options["onSuccess"] == 'function') {
              options["onSuccess"](rawData);
            } else if (typeof options["callback"] == 'function') {
              window.console.log('"callback" option is deprecated, please use "onSuccess" instead.');
              options["callback"](rawData);
            }
          }
        }

        if (options['noQueue']) {
          doIt();
        } else {
          jQuery('document').ready(function() {
            doIt();
          });
        }
      },
      "error": function(errMsg) {
        jQuery(document).ready(function() {
          if (typeof(options["onError"]) == 'function') {
            options["onError"](errMsg);
          } else if (typeof(options["error"]) == 'function') {
            window.console.log('"error" option is deprecated, please use "onError" instead.');
            options["error"](errMsg);
          } else {
            console.log(errMsg);
          }
        });
      }
    };

    if (options["method"].toLowerCase() != "get") {
      ajaxOptions["contentType"] = "application/json";
    }

    jQuery.ajax(ajaxOptions);
  }
  
  self.selectOptions = function(options) {
    var keys = Object.keys(options["selectOptions"]);
  
    if (typeof(options["unsorted"]) != 'undefined' && !options["unsorted"]) {
      keys = keys.sort();
    }
  
    var output = jQuery('<select>');
    for (key in keys) {
      // convert from index location to key name
      key = keys[key];
      var option = jQuery('<option>');
      if (typeof(options['selectOptions'][key]) === 'object') {
        option.attr('value', options['selectOptions'][key]['value']);
        option.html(options['selectOptions'][key]['description']);
        option.attr('title', (options['selectOptions'][key]['tooltip']))
      } else {
        option.attr('value', key);
        option.html(options['selectOptions'][key]);
      }

      if (typeof(options["selected"]) != 'undefined' && options["selected"] == key) {
        option.attr('selected','selected');
      }
      output.append(option);
    }
  
    if (typeof(options["selector"] != 'undefined')) {
      jQuery(options["selector"]).html(output.html());
    }
  }
  
  self.convertToGoogleTable = function(options) {
    if (typeof(jQuery) != 'undefined' && typeof(google) != 'undefined') {
      jQuery(options["tableSelector"]).each(function() {
        var table = jQuery(this);
        table.css('display','none');
      
        var gTableData = new google.visualization.DataTable();
      
        var types = []
        table.find('tr.header').each(function() {
          var tableRow = jQuery(this);
          var i = 0;
          tableRow.find('th').each(function() {
            var col = jQuery(this);
            var type = col.attr('class')
            var value = col.html();
            gTableData.addColumn(type,value);
            types[i] = type;
            i++;
          })  
        })  
      
        var tableData = []; 
        table.find('tr.data').each(function() {
          var tableRow = jQuery(this);
          var row = []; 
          var i = 0;
          tableRow.find('td').each(function() {
            var col = jQuery(this);
            var value;
      
            if (types[i] == 'boolean') {
              value = Boolean(col.html());
            } else if (types[i] == 'number') {
              var formatted = col.html();
              var sortable = col.attr('value');
              if (typeof(sortable) == 'undefined') {
                sortable = parseFloat(formatted);
              } else {
                sortable = parseFloat(sortable);
              }   
              value = { v: sortable, f: formatted };
            } else {
              value = col.html();
            }   
            row.push(value);
            i++;
          })  
          tableData.push(row);
        })  
        gTableData.addRows(tableData);
      
        table.wrap('<div>');
        var wrapperID;
        var wrapperClass;
        if (typeof(options["wrapperID"]) != 'undefined') {
          wrapperID = options["wrapperID"];
        }   
        if (typeof(["wrapperClass"]) != 'undefined') {
          wrapperClass = options["wrapperClass"];
        }   
      
        if (typeof(wrapperID) == 'undefined') {
          wrapperID = 'table-converted-' + Math.random().toString(36).replace(/[^a-z0-9]+/g,'');
        }   
      
        table.parent().attr('id',wrapperID);
      
        if (typeof(wrapperClass) != 'undefined') { 
          table.parent().attr('class',wrapperClass);
        }   
      
        var gTable = new google.visualization.Table(document.getElementById(wrapperID));
      
        if (typeof(options["callback"]) == 'function') {
          options["callback"](gTable,gTableData);
        } else {
          gTable.draw(gTableData, {showRowNumber: false});
        }   
      })  
    }   
  }
  
  self.linkStateSelectorToCountrySelector = function(options) {
    var countrySelector = options["countrySelector"];
    var stateSelector = options["stateSelector"];
  
    jQuery('document').ready(function() {
      jQuery(countrySelector).change(function() {
        var newCountry = jQuery(countrySelector).val();
        self.json({ url: '/admin/api/country/:' + newCountry +'/state',
          method: 'GET',
          callback: function(responseData) {
            var countryList = responseData["content"]["states"];
            var stateOptions = new Object();
            for (var i in countryList) {
              stateOptions[countryList[i]["abbreviation"]] = countryList[i]["commonName"];
            }
            self.selectOptions({ selectOptions: stateOptions, selector: stateSelector});
          }
        });
      });
    });
  }
  
  self.createSpinner = function(name,selector) {
    _spinners[name] = {};
    _spinners[name]['selector'] = selector;
  }

  self.startSpinner = function(name) {
    var spinner = new Spinner(_spinnerOptions).spin();
    jQuery(_spinners[name]['selector']).html(spinner.el);
    _spinners[name]['spinner'] = spinner;
  };

  self.stopSpinner = function(name) {
    _spinners[name]['spinner'].stop();
  }

  self.stringHashCode = function(string) {
    var hash = 0;
    if (string.length == 0) return hash;
    for (i = 0; i < string.length; i++) {
        char = string.charCodeAt(i);
        hash = ((hash<<5)-hash)+char;
        hash = hash & hash; // Convert to 32bit integer
    }
    return hash;
  }

  self.convertToLocalTime = function(dateFromServer) {
    if (dateFromServer != null) {
      dateFromServer = dateFromServer.replace(/-/g, '/');

      // get date using time zone of user
      var date = new Date(dateFromServer + ' UTC');
      var dateAndTime = self.formatDateTime(date, true);

      return dateAndTime;
    }
  }

  self.formatDateTime = function(dateTime, converted) {
    if (dateTime != null) {
        var date;
        if (converted) {
            date = dateTime;
        } else {
            date = new Date(dateTime);
        }
        var day = ("0" + date.getDate()).slice(-2)
        var month = ("0" + (date.getMonth() + 1)).slice(-2);
        var year = (date.getFullYear().toString()).slice(-2);

        // convert to am pm
        var hours = date.getHours() > 12 ? date.getHours() - 12 : date.getHours();
        hours = hours < 10 ? "0" + hours : hours;
        var am_pm = date.getHours() >= 12 ? "PM" : "AM";
        var minutes = date.getMinutes() < 10 ? "0" + date.getMinutes() : date.getMinutes();
        var seconds = date.getSeconds() < 10 ? "0" + date.getSeconds() : date.getSeconds();
        time = hours + ":" + minutes + ":" + seconds + " " + am_pm;

        var dateAndTime = month + "/" + day + "/" + year + " " + time;

        return dateAndTime;
    }
  }

  self.initializeAjaxHandlers = function() {
    jQuery(document).ajaxStart(function() {
      jQuery('.loaderAnimation').show();
      jQuery('input[type=button], input[type=submit], button').css('opacity','0.8').attr('disabled',true);
    });
    jQuery(document).ajaxStop(function() {
      jQuery('.loaderAnimation').hide();
      jQuery('input[type=button], input[type=submit], button').css('opacity','1').attr('disabled',false);
    });
  }
  
  self.setCurrentToken = function(token) {
    self.currentToken = token
  }

  self.formatDateTime = function(dateTime, converted) {
    if (dateTime != null) {
        var date;
        if (converted) {
            date = dateTime;
        } else {
            date = new Date(dateTime);
        }
        var day = ("0" + date.getDate()).slice(-2)
        var month = ("0" + (date.getMonth() + 1)).slice(-2);
        var year = (date.getFullYear().toString()).slice(-2);

        // convert to am pm
        var hours = date.getHours() > 12 ? date.getHours() - 12 : date.getHours();
        hours = hours < 10 ? "0" + hours : hours;
        var am_pm = date.getHours() >= 12 ? "PM" : "AM";
        var minutes = date.getMinutes() < 10 ? "0" + date.getMinutes() : date.getMinutes();
        var seconds = date.getSeconds() < 10 ? "0" + date.getSeconds() : date.getSeconds();
        time = hours + ":" + minutes + ":" + seconds + " " + am_pm;

        var dateAndTime = month + "/" + day + "/" + year + " " + time;

        return dateAndTime;
    }
  }

  self.lastDayOfYear = function(month, year) {
      var shortMonths = {
          4: 30,
          6: 30,
          9: 30,
          11: 30
      };

      if (parseInt(month) === 2) {
          if ((year % 4) === 0) {
              return 29;
          } else {
              return 28;
          }
      } else if (shortMonths[month]) {
          return 30;
      } else {
          return 31;
      }
  };
}

setInterval(function() {
  var currentToken = jQuery('meta[name=request-token]').prop('content')
  var realm = jQuery('meta[name=realm]').prop('content')
  Tools.json({url: '/api/login/',action: 'create', data: {'currentToken': currentToken, 'cookieName': realm}, onSuccess: function(data) {
    jQuery('meta[name=request-token]').prop('content',data['content']['newToken'])
    Tools.setCurrentToken(data['content']['newToken'])
  }})
},60 * 1000)
