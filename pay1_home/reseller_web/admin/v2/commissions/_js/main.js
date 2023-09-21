jQuery(document).ready(function() {

  jQuery('input[name=getReports]').click(function() {
    jQuery('#mainTable').addClass('hidden').children().remove();
    jQuery('#tableWrapper').remove();
    jQuery('#payoutTotals').remove();
    jQuery('div.google-visualization-table').parent().remove();
    jQuery('#tableContainer').append('<span id="loading"><hr><h1>Loading...</h1><hr></span>');

    var urlString = "/admin/api/reseller/commissions/!/startyear/:" + jQuery('select[name=startyear]').val() + "/startmonth/:" + jQuery('select[name=startmonth]').val();
    urlString += "/endyear/:" + jQuery('select[name=endyear]').val() + '/endmonth/:' + jQuery('select[name=endmonth]').val();
    jQuery('input[name=getReports]').prop('disabled',true);
    Tools.json({ url: urlString,
      method: "GET",
      key: 'Commission',
      callback: function(content) {
        var data = content["content"];
        jQuery('#loading h1').text('Building Table...');

        var dataSource = new ChartDataSource;
        var columns = data['table']['columns'];
        for(var index in columns){
          dataSource.addColumn(columns[index]);
        };
   
        var rows = data['table']['data'];
        for(var rowIndex in rows) {
          dataSource.addRow(rows[rowIndex]);
        }
        var chart = new Chart;
        chart.setContainerID(data['table']['id']);
        chart.setAPISpecificOptions({showRowNumber:false,height:'350px',sortColumn:0,sortAscending:true});

        jQuery('#loading').remove();

        var totals = "<div id='payoutTotals'>";
        totals += "<h1>Commission Totals</h1><hr>";
        totals += "<table class='noFinger'><tr><td>Total Paid:</td><td>$" + data['paid'] + "</td></tr>";
        totals += "<tr><td>Total Unpaid:</td><td>$" + data['comm'] + "</td></tr>";
        totals += "<tr><td>Grand Total:</td><td>$" + data['total'] + "</td></tr></table> </div>";

        jQuery('div.tableDiv div.totals').html(totals).show();
        chart.drawTable(dataSource);
        jQuery('#mainTable').removeClass('hidden');
        jQuery('input[name=getReports]').prop('disabled',false);
      },
      error: function() {
        jQuery('#loading').remove();
        var errorNotice = '<label><span id="tableWrapper">No Data Found</span></label><hr>';
        jQuery('input[name=getReports]').prop('disabled',false);
      }
    });
  });
});
