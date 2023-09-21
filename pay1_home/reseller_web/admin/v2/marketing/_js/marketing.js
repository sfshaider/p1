
jQuery(function () {
	
	var url = '/admin/api/marketing/documents';
	
	var options = {};
	options['url'] = url;
	options['method'] = 'GET';
	options['callback'] = successDocs;

	json(options);

});

function successDocs(data) {

	if (typeof(data['content']['documentInfo']) == undefined) {
		return;
	}

	var table = new google.visualization.DataTable();
	
	table.addColumn('string', 'Url');
	table.addColumn('string', 'Title');
	table.addColumn('string', 'Description');

	var list = data['content']['documentInfo'][0];

	for (var row in list) {
		var sub = list[row];
		for (var entry in sub) {
			var url = sub[entry]['url'];
			var title = sub[entry]['title'];
			var description = sub[entry]['description'];
			table.addRow([
				url, title, description
			]);
		}
	}

	var view = new google.visualization.DataView(table);
	view.setColumns([1,2]);

	var chart = new google.visualization.Table(document.getElementById('documentTable'));

	chart.draw(view);

	google.visualization.events.addListener(chart, 'select', function() {

		var selection = chart.getSelection();
		var item = selection[0];
		var str = table.getFormattedValue(item.row, 0);

		window.location = str;

	});

}

jQuery(document).ready(function() {


	jQuery('#submit').click(function() {
		jQuery('#helpdesk').submit();
	});

});

