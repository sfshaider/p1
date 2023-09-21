var ChartDataSource = function() {
	var self = this;
	var _columns = [];
	var _data = [];
	var _validColumnTypes = ['number','string','boolean'];
	var _columnIterator = -1;
	var _rowIterator = -1;
	var _columnIDToColumnIndexMap = {};
	var _pageSize;
	var _page;
	var _sortOrder = 'ascending';
	var _sortColumnIndex;

	/* public functions */
	this.addColumn = function(columnObject) {
		if (_data.length > 0) {
			throw new Error('Can not add column after data has been added');
		}
		var columnName = columnObject["name"];
		var columnType = columnObject["type"];
		var columnID   = columnObject["id"];
		if (typeof(columnName) == 'undefined') {
			throw new Error('Can not add column with an undefined name');
		} else if (typeof(columnType) == 'undefined') {
			throw new Error('Can not add column with an undefined type');
		} else if (typeof(columnID) == 'undefined') {
			throw new Error('Can not add column with an undefined id');
		} else {
			var column = { 'name': columnName,'type': columnType, 'id': columnID };
			_columns.push(column);
			_columnIDToColumnIndexMap[columnID] = (_columns.length - 1);
		}
	}

	this.columns = function(columns) {
		if (typeof(columns) == 'object') {
			_columns = columns;
		}
		return _columns;
	}

	this.column = function(columnID) {
		var columnIndex = _columnIDToColumnIndexMap[columnID];
		if (typeof(columnIndex) == 'undefined') {
			throw new Error('Unknown columnID: ' + columnID);
		}

		// get values as object to remove duplicates
		var columnData = {};
		for (var i = 0; i < _data.length; i++) {
			columnData[(_data[i][columnIndex])] = 1;
		}

		// remove object keys
		var columnValues = [];
		for (var value in columnData) {
			columnValues.push(value);
		}

		return columnValues;
	}

	this.rows = function(rows) {
		if (typeof(rows) == 'object') {
			for (var i = 0; i < rows.length; i++) {
				for (var j = 0; j < rows[i].length; j++) {
					if (rows[i] == null) {
						throw new Error('Undefined/Null data in row element is not allowed');
					}
				}
			}
			_data = rows;
		}
		return _data;
	}


	this.columnNames = function() {
		var names = [];
		for (var i = 0; i < _columns.length; i++) {
			names.push(_columns[i]['name']);
		}
		return names;
	}

	this.addRow = function(rowArray) {
		if (_columns.length == 0) {
			throw new Error('No columns defined');
		}
		if (rowArray.length != _columns.length) {
			throw new Error('Row length does not match the number of columns');
		} else {
			for (var j = 0; j < rowArray.length; j++) {
				if (rowArray[j] == null) {
					throw new Error('Undefined/Null data in row element is not allowed: row: ' + JSON.stringify(rowArray));
				}
			}
			_data.push(rowArray);
		}
	}

	this.removeRow = function(rowIndex) {
		if (_columns.length == 0) {
			throw new Error('No columns defined');
		}
		if (rowIndex > _data.length || rowIndex < 0) {
			throw new Error('Invalid index');
		} else {
			_data.splice(rowIndex, 1);
		}
	}

	this.resetColumnIterator = function() {
		_columnIterator = -1;
	}

	this.resetRowIterator = function() {
		_rowIterator = -1;
		self.resetColumnIterator();
	}

	this.hasNextRow = function() {
		if (_rowIterator < _data.length - 1) {
			return true;
		}
		return false;
	}

	this.hasNextColumn = function() {
		if (_columnIterator < _columns.length - 1) {
			return true;
		}
		return false;
	}

	this.firstRow = function() {
		self.resetRowIterator();
		return self.getNextRow();
	}

	this.nextRow = function() {
		var row;
		if (_rowIterator >= _data.length) {
			throw new Error('No more rows.');
		} else {
			row = _data[_rowIterator];
			_rowIterator++;
			self.resetColumnIterator();
		}
		return row;
	}

	this.nextColumn = function() {
		_columnIterator++;
		var row = _data[_rowIterator];
		var data;
		if (_columnIterator >= _columns.length) {
			throw new Error('No more columns.');
		} else {	
			data = row[_columnIterator];
		}
		return data;
	}

	this.columnType = function() {
		if (_columnIterator > _columns.length) {
			throw new Error('Invalid column');
		} else {
			return _columns[_columnIterator]['type'];
		}
	}

	this.filter = function(filters) {
		if (typeof(filters) == 'object') {
			var filteredCopy = self.cloneColumnsOnly();
			var _dataCopy = JSON.parse(JSON.stringify(_data));
			for (var filter in filters) {
				var columnID = filters[filter]["columnID"];
				var match = filters[filter]["filter"];

				var columnIndex = _columnIDToColumnIndexMap[columnID];

				var isDatetime = false;
				if (_columns[columnIndex]['type'] == 'datetime') {
					isDatetime = true;
				}

				/* loop through all rows and delete rows that do not match */
				var rowIndex = 0;
				while (rowIndex < _dataCopy.length) {
			
					/* if type is datetime, this corrects the format for better matching */	
					var str = _dataCopy[rowIndex][columnIndex].toString(); 
					if (isDatetime) {
						str = new Date(str).toString();
					}

					/* if splice is run, array gets shorter so we do not increment */
					if (str.match(match) == null) {
						/* remove the row */
						_dataCopy.splice(rowIndex,1);
					} else {
						rowIndex++;
					}
				}
			}

			filteredCopy.rows(_dataCopy);
			return filteredCopy;
		}
		return self;
	}

	this.clone = function() {
		var copy = new ChartDataSource();
		copy.columns(_columns);
		copy.rows(_data);
		copy.setSortColumnIndex(_sortColumnIndex);
		copy.setSortOrder(_sortOrder);
		copy.setPageSize(_pageSize);
		return copy;
	}

	this.cloneColumnsOnly = function() {
		var copy = new ChartDataSource();
		copy.columns(_columns);
		copy.setSortColumnIndex(_sortColumnIndex);
		copy.setSortOrder(_sortOrder);
		copy.setPageSize(_pageSize);
		return copy;
	}

	this.logState = function() {
		var state = {};
		state["rowIterator"] = _rowIterator;
		state["columnIterator"] = _columnIterator;
		state["data"] = _data;
		console.log(state);
	}

	this.setPageSize = function(size) {
		_pageSize = size;
	}

	this.getPageSize = function() {
		if (typeof(_pageSize) == 'undefined') {
			return 100;
		}
		return _pageSize;
	}

	this.getPage = function(pageNumber) {
		var pageCopy = self.cloneColumnsOnly();
		var pageSize = self.getPageSize();

		var start = pageNumber*pageSize;
		var end = (pageNumber*pageSize)+pageSize;

		var dataSlice = _data.slice(start,end);
		pageCopy.rows(dataSlice);
		return pageCopy;
	}

	this.setSortColumnID = function(columnID) {
		_sortColumnIndex = _columnIDToColumnIndexMap[columnID];
	}

	this.setSortColumnIndex = function(index) {
		_sortColumnIndex = index;
	}

	this.getSortColumnID = function() {
		for (var columnID in _columIDToColumnIndexMap) {
			if (_columnIDToColumIndexMap[columnID] == _sortColumnIndex) {
				return columnID;
			}
		}
	}

	this.getSortColumnIndex = function() {
		if (typeof(_sortColumnIndex) == 'undefined') {
			return 0;
		}
		return _sortColumnIndex;
	}

	this.setSortOrder = function(order) {
		if (!(order == 'ascending' || order == 'descending')) {
			_sortOrder = 'ascending';
		} else {
			_sortOrder = order;
		}
	}

	this.getSortOrder = function() {
		if (typeof(_sortOrder) == 'undefined') {
			return 'ascending';
		}
		return _sortOrder;
	}

	this.sort = function() {
		if (typeof(_sortOrder) != 'undefined') {
			_data.sort(function(a,b) {
				var descending = (_sortOrder == 'descending' ? -1 : 1);
				var i = self.getSortColumnIndex();
				var value1 = a[i];
				var value2 = b[i];

				return (value1 > value2 ? 1 : -1) * descending;
			});
		}
	}
}


var Chart = function() {
	var self = this;
	var _containerID;
	var _apiSpecificOptions;
	var _callback;
	var _drawFunction;

	this.setContainerID = function(containerID) {
		_containerID = containerID;
	}

	this.setAPISpecificOptions = function(options) {
		_apiSpecificOptions = options;
	}

	this.setCallback = function(callback) {
		_callback = callback;
	}

	this.setDrawFunction = function(drawFunction) {
		_drawFunction = drawFunction;
	}

	this.drawTable = function(tableDataSource) {
		var googleData = new google.visualization.DataTable();

		tableDataSource.resetRowIterator();

		var columns = tableDataSource.columns();
		for (var i = 0; i < columns.length; i++) {
			googleData.addColumn(columns[i]['type'], columns[i]['name']);
		}

		while (tableDataSource.hasNextRow()) {
			var dataRow = tableDataSource.nextRow();
			var row = [];
			while(tableDataSource.hasNextColumn()) {
				var column = tableDataSource.nextColumn();
				var googleColumn;
				if (tableDataSource.columnType() == 'number') {
					var value = parseFloat(column.toString().replace(/[^\d\.]/gi,''));
					var formatted = column.toString();
					googleColumn = { 'v': value, 'f': formatted };
				} else if (tableDataSource.columnType() == 'datetime') {
					googleColumn = new Date(column.toString());
				} else {
					googleColumn = column;
				}
				row.push(googleColumn);
			}
			googleData.addRow(row); 
		}

		var googleTable = new google.visualization.Table(document.getElementById(_containerID));

		var options;
		if (typeof(_apiSpecificOptions) == 'undefined') {
			options = {};
		} else {
			options = _apiSpecificOptions;
		}

		if (typeof(_callback) == 'function') {
			options['callback'] = _callback;
		}

		if (typeof(_drawFunction) == 'function') {
			_drawFunction(googleTable,googleData,options);
		} else {
			googleTable.draw(googleData,options);
		}
	}
}
