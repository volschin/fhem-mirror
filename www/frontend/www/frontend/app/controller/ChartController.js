/**
 * Controller handling the charts
 */
Ext.define('FHEM.controller.ChartController', {
    extend: 'Ext.app.Controller',
    /**
     * maxValue of Y Axis gets saved here as reference
     */
    maxYValue: 0,
    
    /**
     * minValue of Y Axis gets saved here as reference
     */
    minYValue: 9999999,
    
    /**
     * maxValue of Y2 Axis gets saved here as reference
     */
    maxY2Value: 0,
    
    /**
     * minValue of Y2 Axis gets saved here as reference
     */
    minY2Value: 9999999,

    refs: [
           {
               selector: 'panel[name=chartformpanel]',
               ref: 'chartformpanel' //this.getChartformpanel()
           },
           {
               selector: 'datefield[name=starttimepicker]',
               ref: 'starttimepicker' //this.getStarttimepicker()
           },
           {
               selector: 'datefield[name=endtimepicker]',
               ref: 'endtimepicker' //this.getEndtimepicker()
           },
           {
               selector: 'button[name=requestchartdata]',
               ref: 'requestchartdatabtn' //this.getRequestchartdatabtn()
           },
           {
               selector: 'button[name=savechartdata]',
               ref: 'savechartdatabtn' //this.getSavechartdatabtn()
           },
           {
               selector: 'chart',
               ref: 'chart' //this.getChart()
           },
           {
               selector: 'chartformpanel',
               ref: 'panel[name=chartformpanel]' //this.getChartformpanel()
           },
           {
               selector: 'linechartpanel',
               ref: 'linechartpanel' //this.getLinechartpanel()
           },
           {
               selector: 'linechartpanel toolbar',
               ref: 'linecharttoolbar' //this.getLinecharttoolbar()
           },
           {
               selector: 'grid[name=chartdata]',
               ref: 'chartdatagrid' //this.getChartdatagrid()
           },
           {
               selector: 'panel[name=maintreepanel]',
               ref: 'maintreepanel' //this.getMaintreepanel()
           }
    ],

    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'button[name=requestchartdata]': {
                click: this.requestChartData
            },
            'button[name=savechartdata]': {
                click: this.saveChartData
            },
            'button[name=stepback]': {
                click: this.stepchange
            },
            'button[name=stepforward]': {
                click: this.stepchange
            },
            'button[name=resetchartform]': {
                click: this.resetFormFields
            },
            'menuitem[name=deletechartfromcontext]': {
                click: this.deletechart
            },
            'menuitem[name=renamechartfromcontext]': {
                click: this.renamechart
            },
            'treepanel[name=maintreepanel]': {
                itemclick: this.loadsavedchart
            },
            'treeview': {
                drop: this.movenodeintree
            },
            'grid[name=chartdata]': {
                itemclick: this.highlightRecordInChart
            },
            'panel[name=chartpanel]': {
                collapse: this.resizeChart,
                expand: this.resizeChart
            },
            'panel[name=chartformpanel]': {
                collapse: this.resizeChart,
                expand: this.resizeChart
            },
            'panel[name=chartgridpanel]': {
                collapse: this.resizeChart,
                expand: this.resizeChart
            }
        });
        
    },
    
    /**
     * Triggers a request to FHEM Module to get the data from Database
     */
    requestChartData: function(stepchangecalled) {
        
        var me = this;
        
        //show loadmask
        me.getLinechartpanel().setLoading(true);
        
        //timeout needed for loadmask to appear
        window.setTimeout(function() {
        
            //suspending complex layouts
            Ext.suspendLayouts();
            
            //getting the necessary values
            var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]'),
                yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]'),
                yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]'),
                yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]'),
                yaxesstepcheck = Ext.ComponentQuery.query('checkbox[name=yaxisstepcheck]'),
                yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]'),
                axissideradio = Ext.ComponentQuery.query('radiogroup[name=axisside]');
            
            var starttime = me.getStarttimepicker().getValue(),
                dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
                endtime = me.getEndtimepicker().getValue(),
                dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
                dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
                chartpanel = me.getLinechartpanel(),
                chart = me.getChart();
            
            //cleanup chartpanel 
            var existingwins = Ext.ComponentQuery.query('window[name=statisticswin]');
            Ext.each(existingwins, function(existingwin) {
                existingwin.destroy();
            });
            
            var existingchartgrid = Ext.ComponentQuery.query('panel[name=chartgridpanel]')[0];
            if (!existingchartgrid) {
                var chartdatagrid = Ext.create('FHEM.view.ChartGridPanel', {
                    name: 'chartgridpanel',
                    minHeight: 200,
                    maxHeight: 200,
                    collapsed: true
                });
                chartpanel.add(chartdatagrid);
            } else {
                existingchartgrid.down('grid').getStore().removeAll();
            }
            var existingchart = Ext.ComponentQuery.query('panel[name=chartpanel]')[0];
            if (!existingchart) {
                var store = Ext.create('FHEM.store.ChartStore'),
                    proxy = store.getProxy();
                chart = me.createChart(store);
                chartpanel.add(chart);
            } else {
                chart.getStore().removeAll();
                chart.getStore().destroy();
                //removes the store completely from chart
                chart.bindStore();
                var chartstore = Ext.create('FHEM.store.ChartStore');
                chart.bindStore(chartstore);
                chart.series.removeAll();
                chart.axes.get(0).setTitle("");
                chart.axes.get(1).setTitle("");
            }
            
            //reset zoomValues
            chartpanel.setLastYmax(null);
            chartpanel.setLastYmin(null);
            chartpanel.setLastXmax(null);
            chartpanel.setLastXmin(null);
            
            me.maxYValue = 0;
            me.minYValue = 9999999;
            me.maxY2Value = 0;
            me.minY2Value = 9999999;
            
            //check if timerange or dynamic time should be used
            dynamicradio.eachBox(function(box, idx){
                var date = new Date();
                if (box.checked && stepchangecalled !== true) {
                    if (box.inputValue === "year") {
                        starttime = Ext.Date.parse(date.getUTCFullYear() + "-01-01", "Y-m-d");
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                        endtime = Ext.Date.parse(date.getUTCFullYear() +  1 + "-01-01", "Y-m-d");
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                    } else if (box.inputValue === "month") {
                        starttime = Ext.Date.getFirstDateOfMonth(date);
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                        endtime = Ext.Date.getLastDateOfMonth(date);
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                    } else if (box.inputValue === "week") {
                        date.setHours(0);
                        date.setMinutes(0);
                        date.setSeconds(0);
                        //monday starts with 0 till sat with 5, sund with -1
                        var dayoffset = date.getDay() - 1,
                            monday,
                            nextmonday;
                        if (dayoffset >= 0) {
                            monday = Ext.Date.add(date, Ext.Date.DAY, -dayoffset);
                        } else {
                            //we have a sunday
                            monday = Ext.Date.add(date, Ext.Date.DAY, -6);
                        }
                        nextmonday = Ext.Date.add(monday, Ext.Date.DAY, 7);
                        
                        starttime = monday;
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                        endtime = nextmonday;
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                        
                    } else if (box.inputValue === "day") {
                        date.setHours(0);
                        date.setMinutes(0);
                        date.setSeconds(0);
                        
                        starttime = date;
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                        endtime = Ext.Date.add(date, Ext.Date.DAY, 1);
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                        
                    } else if (box.inputValue === "hour") {
                        date.setMinutes(0);
                        date.setSeconds(0);
                        
                        starttime = date;
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                        endtime = Ext.Date.add(date, Ext.Date.HOUR, 1);
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                    } else {
                        Ext.Msg.alert("Error", "Could not setup the dynamic time.");
                    }
                    me.getStarttimepicker().setValue(starttime);
                    me.getEndtimepicker().setValue(endtime);
                }
            });
            
            var i = 0;
            Ext.each(yaxes, function(y) {
                var device = devices[i].getValue(),
                    yaxis = yaxes[i].getValue(),
                    yaxiscolorcombo = yaxescolorcombos[i].getValue(),
                    yaxisfillcheck = yaxesfillchecks[i].checked,
                    yaxisstepcheck = yaxesstepcheck[i].checked,
                    yaxisstatistics = yaxesstatistics[i].getValue(),
                    axisside = axissideradio[i].getChecked()[0].getSubmitValue();
                if(yaxis === "" || yaxis === null) {
                    yaxis = yaxes[i].getRawValue();
                }
                
                me.populateAxis(i, yaxes.length, device, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstepcheck, axisside, yaxisstatistics, dbstarttime, dbendtime);
                i++;
            });
            
        }, 300);
    },
    
    /**
     * resize the chart to fit the centerpanel
     */
    resizeChart: function() {
        
        var lcp = Ext.ComponentQuery.query('linechartpanel')[0];
        var lcv = Ext.ComponentQuery.query('chart')[0];
        var cfp = Ext.ComponentQuery.query('form[name=chartformpanel]')[0];
        var cdg = Ext.ComponentQuery.query('panel[name=chartgridpanel]')[0];
        
        // disable animation as long as we resize, causes serious performance issues
        lcv.animate = false;
        
        if (lcp && lcv && cfp && cdg) {
            var lcph = lcp.getHeight(),
                lcpw = lcp.getWidth(),
                cfph = cfp.getHeight(),
                cdgh = cdg.getHeight();
            
            if (lcph && lcpw && cfph && cdgh) {
                var chartheight = lcph - cfph - cdgh - 80;
                var chartwidth = lcpw - 5;
                lcv.height = chartheight;
                lcv.width = chartwidth;
                //render after 50ms to get component right
                window.setTimeout(function() {
                    if (lcv.series.get(0).hideAll) {
                        lcv.series.get(0).hideAll();
                    }
                    lcv.doComponentLayout();
                    if (lcv.series.get(0).showAll) {
                        lcv.series.get(0).showAll();
                    }
                    lcv.redraw();
                }, 50);
            }
        }
        lcv.animate = true;
    },
    
    /**
     * create the base chart
     */
    createChart: function(store) {
        var me = this;
        
        var chart = Ext.create('Ext.panel.Panel', {
            title: 'Chart',
            name: 'chartpanel',
            collapsible: true,
            titleCollapse: true,
            animCollapse: false,
            items: [
                {
                    xtype: 'toolbar',
                    items: [
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Step back',
                            name: 'stepback',
                            icon: 'app/resources/icons/resultset_previous.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Step forward',
                            name: 'stepforward',
                            icon: 'app/resources/icons/resultset_next.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Reset Zoom',
                            name: 'resetzoom',
                            icon: 'app/resources/icons/delete.png',
                            scope: me,
                            handler: function(btn) {
                                var chart = btn.up().up().down('chart');
                                
                                var existingwins = Ext.ComponentQuery.query('window[name=statisticswin]');
                                Ext.each(existingwins, function(existingwin) {
                                    existingwin.destroy();
                                });
                                
                                chart.restoreZoom();
                                
                                chart.axes.get(0).minimum = chart.up().up().getLastYmin();
                                chart.axes.get(0).maximum = chart.up().up().getLastYmax();
                                chart.axes.get(1).minimum = chart.up().up().getLastY2min();
                                chart.axes.get(1).maximum = chart.up().up().getLastY2max();
                                chart.axes.get(2).minimum = chart.up().up().getLastXmin();
                                chart.axes.get(2).maximum = chart.up().up().getLastXmax();
                                
                                chart.redraw();
                                //helper to reshow the hidden items after zooming back out
                                if (chart.up().up().artifactSeries && chart.up().up().artifactSeries.length > 0) {
                                    Ext.each(chart.up().up().artifactSeries, function(serie) {
                                        serie.showAll();
                                        Ext.each(serie.group.items, function(item) {
                                            if (item.type === "circle") {
                                                item.show();
                                                item.redraw();
                                            }
                                        });
                                    });
                                    chart.up().up().artifactSeries = [];
                                }
                            }
                        }
                    ]
                },
                {
                    xtype: 'chart',
                    legend: {
                        position: 'right',
                        labelFont: '10px Helvetica, sans-serif',
                        padding: 4
                    },
                    axes: [ 
                        {
                            type : 'Numeric',
                            name : 'yaxe',
                            position : 'left',
                            fields : [],
                            title : '',
                            grid : {
                                odd : {
                                    opacity : 1,
                                    fill : '#ddd',
                                    stroke : '#bbb',
                                    'stroke-width' : 0.5
                                }
                            }
                        }, 
                        {
                            type : 'Numeric',
                            name : 'yaxe2',
                            position : 'right',
                            fields : [],
                            title : ''
                        }, 
                        {
                            type : 'Time',
                            name : 'xaxe',
                            position : 'bottom',
                            fields : [ 'TIMESTAMP' ],
                            dateFormat : "Y-m-d H:i:s",
                            title : 'Time'
                        }
                    ],
                    animate: false,
                    shadow: false,
                    store: store,
                    enableMask: true,
                    mask: true,//'vertical',//true, //'horizontal',
                    listeners: {
                        mousedown: function(evt) {
                            // fix for firefox, not dragging images
                            evt.preventDefault();
                        },
                        select: {
                            fn: function(chart, zoomConfig, evt) {
                                
                                delete chart.axes.get(2).fromDate;
                                delete chart.axes.get(2).toDate;
                                chart.up().up().setLastYmax(chart.axes.get(0).maximum);
                                chart.up().up().setLastYmin(chart.axes.get(0).minimum);
                                chart.up().up().setLastY2max(chart.axes.get(1).maximum);
                                chart.up().up().setLastY2min(chart.axes.get(1).minimum);
                                chart.up().up().setLastXmax(chart.axes.get(2).maximum);
                                chart.up().up().setLastXmin(chart.axes.get(2).minimum);
                                
                                chart.setZoom(zoomConfig);
                                chart.mask.hide();
                                
                                //helper hiding series and items which are out of scope
                                Ext.each(chart.series.items, function(serie) {
                                    if (serie.items.length === 0) {
                                        chart.up().up().artifactSeries.push(serie);
                                        Ext.each(serie.group.items, function(item) {
                                            item.hide();
                                            item.redraw();
                                        });
                                        serie.hideAll();
                                        
                                    } else {
                                        //creating statistic windows after zooming
                                        var html,
                                            count = 0,
                                            sum = 0,
                                            average = 0,
                                            min = 99999999,
                                            max = 0,
                                            lastrec,
                                            diffkwh = 0,
                                            winwidth = 125,
                                            winheight = 105;
                                        Ext.each(serie.items, function(item) {
                                            if (Ext.isNumeric(item.value[1])) {
                                                count++;
                                                sum = sum + item.value[1];
                                                if (min > item.value[1]) {
                                                    min = item.value[1];
                                                }
                                                if (max < item.value[1]) {
                                                    max = item.value[1];
                                                }
                                                if (serie.title.indexOf('actual_kwh') >= 0) {
                                                    if (lastrec) {
                                                        var diffhrs = Ext.Date.getElapsed(lastrec.value[0], item.value[0]) / 1000 / 3600;
                                                        diffkwh = diffkwh + diffhrs * lastrec.value[1];
                                                    }
                                                    lastrec = item;
                                                    winwidth = 165,
                                                    winheight = 130;
                                                }
                                            }
                                        });
                                        average = sum / count;
                                        
                                        html = '<b>Selected Items: </b>' + count + '<br>';
                                        html += '<b>Sum: </b>' + Ext.util.Format.round(sum, 5) + '<br>';
                                        html += '<b>Average: </b>' + Ext.util.Format.round(average, 5) + '<br>';
                                        html += '<b>Min: </b>' + min + '<br>';
                                        html += '<b>Max: </b>' + max + '<br>';
                                        if (serie.title.indexOf('actual_kwh') >= 0) {
                                            html += '<b>Used kW/h: </b>' + Ext.util.Format.round(diffkwh, 3) + '<br>';
                                            html += '<b>Costs (at 25c/kWh): </b>' + Ext.util.Format.round(diffkwh * 0.25, 2) + '€<br>';
                                        }
                                        
                                        var existingwins = Ext.ComponentQuery.query('window[name=statisticswin]'),
                                            matchfound = false,
                                            lastwin,
                                            win;
                                        if (existingwins.length > 0) {
                                            Ext.each(existingwins, function(existingwin) {
                                                lastwin = existingwin;
                                                if (existingwin.title === serie.title) {
                                                    existingwin.update(html);
                                                    existingwin.showAt(chart.getWidth() - 145, chart.getPosition()[1] + 8);
                                                    matchfound = true;
                                                } 
                                            });
                                            if (!matchfound) {
                                                win = Ext.create('Ext.window.Window', {
                                                    width: winwidth,
                                                    height: winheight,
                                                    html: html,
                                                    title: serie.title,
                                                    name: 'statisticswin',
                                                    preventHeader: true,
                                                    border: false,
                                                    plain: true
                                                });
                                                win.showAt(chart.getWidth() - 145, lastwin.getPosition()[1] + lastwin.getHeight());
                                            }
                                        } else {
                                            win = Ext.create('Ext.window.Window', {
                                                width: winwidth,
                                                height: winheight,
                                                html: html,
                                                title: serie.title,
                                                name: 'statisticswin',
                                                preventHeader: true,
                                                border: false,
                                                plain: true
                                            });
                                            win.showAt(chart.getWidth() - 145, chart.getPosition()[1] + 8);
                                        }
                                    }
                                });
                            }
                        }
                    }
                }    
            ]
        });
        
        return chart;
    },
    
    /**
     * creating baselines
     */
    createBaseLine: function(index, basestart, baseend, basefill, basecolor) {
        var me = this,
            chart = me.getChart(),
            store = chart.getStore(),
            yfield = "VALUEBASE" + index;
        
        if (!Ext.isEmpty(basestart) && basestart != "null") {
            var baseline = {
                type : 'line',
                name: 'baseline',
                axis : 'left',
                xField : 'TIMESTAMP',
                yField : yfield,
                showInLegend: false,
                highlight: true,
                fill: basefill,
                style: {
                    fill : basecolor,
                    'stroke-width': 3,
                    stroke: basecolor
                },
                tips : {
                    trackMouse : true,
                    mouseOffset: [1,1],
                    showDelay: 1000,
                    width : 280,
                    height : 50,
                    renderer : function(storeItem, item) {
                        this.setTitle(' Value: : ' + storeItem.get(yfield) + 
                                '<br> Time: ' + storeItem.get('TIMESTAMP'));
                    }
                }
            };
            chart.series.add(baseline);
            
            store.first().set(yfield, basestart);
            
            //getting the very last items time
            var time = new Date("1970");
            store.each(function(rec) {
                current = rec.get("TIMESTAMP");
                if (current > time) {
                    time = current;
                }
            });
            var item = Ext.create('FHEM.model.ChartModel');
            item.set(yfield, baseend);
            item.set('TIMESTAMP', time);
            store.add(item);
        }
    },
    
    /**
     * fill the axes with data
     */
    populateAxis: function(i, axeslength, device, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstepcheck, axisside, yaxisstatistics, dbstarttime, dbendtime) {
        
        var me = this,
            chart = me.getChart(),
            store = chart.getStore(),
            proxy = store.getProxy(),
            yseries,
            generalization = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
            generalizationfactor = Ext.ComponentQuery.query('combobox[name=genfactor]')[0].getValue();
        
        if (i > 0) {
            yseries = me.createSeries('VALUE' + (i + 1), device + " - " + yaxis, yaxisfillcheck, yaxiscolorcombo, axisside);
        } else {
            yseries = me.createSeries('VALUE', device + " - " + yaxis, yaxisfillcheck, yaxiscolorcombo, axisside);
        }
        
        var url;
        if (!Ext.isDefined(yaxisstatistics) || yaxisstatistics === "none" || Ext.isEmpty(yaxisstatistics)) {
            url += '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
            url +=device + '+timerange+' + "TIMESTAMP" + '+' + yaxis;
            url += '&XHR=1'; 
        } else { //setup url to get statistics
            url += '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
            url +=device;
            
            if (yaxisstatistics.indexOf("hour") === 0) {
                url += '+hourstats+';
            } else if (yaxisstatistics.indexOf("day") === 0) {
                url += '+daystats+';
            } else if (yaxisstatistics.indexOf("week") === 0) {
                url += '+weekstats+';
            } else if (yaxisstatistics.indexOf("month") === 0) {
                url += '+monthstats+';
            } else if (yaxisstatistics.indexOf("year") === 0) {
                url += '+yearstats+';
            }
            
            url += 'TIMESTAMP' + '+' + yaxis;
            url += '&XHR=1'; 
            
        }
        
        Ext.Ajax.request({
          method: 'GET',
          async: false,
          disableCaching: false,
          url: url,
          success: function(response){
              
              var json = Ext.decode(response.responseText);
              
              if (json.success && json.success === "false") {
                  Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i + ", error was: <br>" + json.msg);
              } else {
                  
                  //get the current value descriptor
                  var valuetext;
                  if (yaxisstatistics.indexOf("none") >= 0) {
                      if (i === 0) {
                          valuetext = 'VALUE';
                          yseries.yField = 'VALUE';
                          yseries.tips.renderer = me.setSeriesRenderer('VALUE');
                      } else {
                          valuetext = 'VALUE' + (i + 1);
                          yseries.yField = 'VALUE' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('VALUE' + (i + 1));
                      }
                  } else if (yaxisstatistics.indexOf("sum") > 0) {
                      if (i === 0) {
                          valuetext = 'SUM';
                          yseries.yField = 'SUM';
                          yseries.tips.renderer = me.setSeriesRenderer('SUM');
                      } else {
                          valuetext = 'SUM' + (i + 1);
                          yseries.yField = 'SUM' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('SUM' + (i + 1));
                      }
                  } else if (yaxisstatistics.indexOf("average") > 0)  {
                      if (i === 0) {
                          valuetext = 'AVG';
                          yseries.yField = 'AVG';
                          yseries.tips.renderer = me.setSeriesRenderer('AVG');
                      } else {
                          valuetext = 'AVG' + (i + 1);
                          yseries.yField = 'AVG' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('AVG' + (i + 1));
                      }
                  } else if (yaxisstatistics.indexOf("min") > 0)  {
                      if (i === 0) {
                          valuetext = 'MIN';
                          yseries.yField = 'MIN';
                          yseries.tips.renderer = me.setSeriesRenderer('MIN');
                      } else {
                          valuetext = 'MIN' + (i + 1);
                          yseries.yField = 'MIN' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('MIN' + (i + 1));
                      }
                  }  else if (yaxisstatistics.indexOf("max") > 0)  {
                      if (i === 0) {
                          valuetext = 'MAX';
                          yseries.yField = 'MAX';
                          yseries.tips.renderer = me.setSeriesRenderer('MAX');
                      } else {
                          valuetext = 'MAX' + (i + 1);
                          yseries.yField = 'MAX' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('MAX' + (i + 1));
                      }
                  }  else if (yaxisstatistics.indexOf("count") > 0)  {
                      if (i === 0) {
                          valuetext = 'COUNT';
                          yseries.yField = 'COUNT';
                          yseries.tips.renderer = me.setSeriesRenderer('COUNT');
                      } else {
                          valuetext = 'COUNT' + (i + 1);
                          yseries.yField = 'COUNT' + (i + 1);
                          yseries.tips.renderer = me.setSeriesRenderer('COUNT' + (i + 1));
                      }
                  }
                  
                  //as we have the valuetext, we can fill the grid
                  //fill the grid with the data
                  me.fillChartGrid(json.data, valuetext);
                  
                  var timestamptext;
                  if (i === 0) {
                      timestamptext = 'TIMESTAMP';
                  } else {
                      timestamptext = 'TIMESTAMP' + (i + 1);
                  }
                  
                  //add records to store
                  for (var j = 0; j < json.data.length; j++) {
                      
                      var item = Ext.create('FHEM.model.ChartModel');
                      Ext.iterate(item.data, function(key, value) {
                          if (key.indexOf("TIMESTAMP") >= 0) {
                              item.set(key, json.data[j].TIMESTAMP);
                          }
                      });
                      
                      var valuestring = eval('json.data[j].' + valuetext.replace(/[0-9]/g, ''));
                      
                      //parseFloat only when we got a numeric value, else textparsing in model will fail
                      if (Ext.isNumeric(valuestring)) {
                          valuestring = parseFloat(valuestring, 10);
                      }
                      item.set(valuetext, valuestring);
                      item.set(timestamptext, json.data[j].TIMESTAMP);
                      
                      //check if we have to ues steps
                      //if yes, create a new record with the same value as the last one
                      //and a timestamp 1 millisecond less than the actual record to add.
                      //only do this, when last record is from same axis
                      if(yaxisstepcheck) {
                          if (store.last() && !Ext.isEmpty(store.last().get(valuetext)) && store.last().get(valuetext) !== "") {
                              var lastrec = store.last();
                              var datetomodify = Ext.Date.parse(json.data[j].TIMESTAMP, "Y-m-d H:i:s");
                              var modtimestamp = Ext.Date.add(datetomodify, Ext.Date.MILLI, -1);
                              var stepitem = lastrec.copy();
                              Ext.iterate(stepitem.data, function(key, value) {
                                  if (key.indexOf("TIMESTAMP") >= 0) {
                                      stepitem.set(key, modtimestamp);
                                  }
                              });
                              store.add(stepitem);
                          } 
                      }
                      store.add(item);
                      
                      //rewrite of valuestring to get always numbers, even when text as value was passed to model
                      valuestring = item.get(valuetext);
                      
                      // recheck if our min and max values are still valid
                      if (yseries.axis === "left") {
                          if (me.minYValue > valuestring) {
                              me.minYValue = valuestring;
                          }
                          if (me.maxYValue < valuestring) {
                              me.maxYValue = valuestring;
                          }
                      } else if (yseries.axis === "right") {
                          if (me.minY2Value > valuestring) {
                              me.minY2Value = valuestring;
                          }
                          if (me.maxY2Value < valuestring) {
                              me.maxY2Value = valuestring;
                          }
                      }
                     
                  }
                  
                  if (generalization.checked) {
                      me.generalizeChartData(generalizationfactor, i);
                  }
                  
              } 
          },
          failure: function() {
              Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i);
          }
        });
      
        chart.series.add(yseries);
        
        //check if we have added the last dataset
        if ((i + 1) === axeslength) {
            //add baselines
            var j = 0,
                basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]'),
                basesend = Ext.ComponentQuery.query('numberfield[name=baseend]'),
                basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]'),
                basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
            
            Ext.each(basesstart, function(base) {
                var basestart = basesstart[j].getValue(),
                    baseend = basesend[j].getValue(),
                    basecolor = basescolors[j].getValue(),
                    basefill = basesfills[j].checked;
                
                me.createBaseLine(j + 1, basestart, baseend, basefill, basecolor);
                
                //adjust min and max on y axis
                if (me.maxYValue < basestart) {
                    me.maxYValue = basestart;
                }
                if (me.minYValue > basestart) {
                    me.minYValue = basestart;
                }
                if (me.maxYValue < baseend) {
                    me.maxYValue = baseend;
                }
                if (me.minYValue > baseend) {
                    me.minYValue = baseend;
                }
                j++;
            });
            me.doFinalChartLayout(chart);
        }
    },
    
    /**
     * do the final layout of chart after all data is loaded
     */
    doFinalChartLayout: function(chart) {
        var me = this,
            leftaxisconfiguration = Ext.ComponentQuery.query('radiogroup[name=leftaxisconfiguration]')[0].getChecked()[0].inputValue,
            rightaxisconfiguration = Ext.ComponentQuery.query('radiogroup[name=rightaxisconfiguration]')[0].getChecked()[0].inputValue;
        
        //remove the old max values of y axis to get a dynamic range
        delete chart.axes.get(0).maximum;
        delete chart.axes.get(0).minimum;
        delete chart.axes.get(1).maximum;
        delete chart.axes.get(1).minimum;
        
        
        chart.axes.get(0).maximum = me.maxYValue;
        chart.axes.get(1).maximum = me.maxY2Value;
        
        // adopt the values from the other y-axis, if we have no values assigned at all
        if (chart.axes.get(0).maximum === 0 && chart.axes.get(1).maximum > 0) {
            chart.axes.get(0).maximum = chart.axes.get(1).maximum;
        }
        if (me.minYValue === 9999999 && me.minY2Value < 9999999) {
            chart.axes.get(0).minimum = me.minY2Value;
        } else {
            chart.axes.get(0).minimum = me.minYValue;
        }
        
        if (chart.axes.get(1).maximum === 0 && chart.axes.get(0).maximum > 0) {
            chart.axes.get(1).maximum = chart.axes.get(0).maximum;
        }
        if (me.minY2Value === 9999999 && me.minYValue < 9999999) {
            chart.axes.get(1).minimum = me.minYValue;
        } else {
            chart.axes.get(1).minimum = me.minY2Value;
        }
        
        //if user has specified its own range, use it
        if (leftaxisconfiguration === "manual") {
            var leftaxismin = Ext.ComponentQuery.query('numberfield[name=leftaxisminimum]')[0].getValue(),
                leftaxismax = Ext.ComponentQuery.query('numberfield[name=leftaxismaximum]')[0].getValue();
            
            if (Ext.isNumeric(leftaxismin) && Ext.isNumeric(leftaxismax)) {
                chart.axes.get(0).minimum = leftaxismin;
                chart.axes.get(0).maximum = leftaxismax;
            } else {
                Ext.Msg.alert("Error", "Please select a valid minimum and maximum for the axis!");
            }
        }
        if (rightaxisconfiguration === "manual") {
            var rightaxismin = Ext.ComponentQuery.query('numberfield[name=rightaxisminimum]')[0].getValue(),
                rightaxismax = Ext.ComponentQuery.query('numberfield[name=rightaxismaximum]')[0].getValue();
            
            if (Ext.isNumeric(rightaxismin) && Ext.isNumeric(rightaxismax)) {
                chart.axes.get(1).minimum = rightaxismin;
                chart.axes.get(1).maximum = rightaxismax;
            } else {
                Ext.Msg.alert("Error", "Please select a valid minimum and maximum for the axis!");
            }
        }
        
        // set the x axis range dependent on user given timerange
        var starttime = new Date(me.getStarttimepicker().getValue()),
            endtime = new Date(me.getEndtimepicker().getValue());
        
        chart.axes.get(2).fromDate = starttime;
        chart.axes.get(2).toDate = endtime;
        
        
        var timediffhrs = Ext.Date.getElapsed(chart.axes.get(2).fromDate, chart.axes.get(2).toDate) / 1000 / 3600;
        
        if (timediffhrs <= 1) {
            chart.axes.get(2).step = [Ext.Date.MINUTE, 10];
        } else if (timediffhrs <= 24) {
            chart.axes.get(2).step = [Ext.Date.HOUR, 1];
        } else if (timediffhrs <= 168) {
            chart.axes.get(2).step = [Ext.Date.DAY, 1];
        } else if (timediffhrs <= 720) {
            chart.axes.get(2).step = [Ext.Date.DAY, 7];
        } else if (timediffhrs < 720) {
            chart.axes.get(2).step = [Ext.Date.MONTH, 1];
        }
        
        chart.axes.get(2).processView();
        
        me.resizeChart();
        
        me.getLinechartpanel().setLoading(false);
        
        //enable animation
        chart.animate = true;
        
    },
    
    /**
     * create a single series for the chart
     */
    createSeries: function(yfield, title, fill, color, axisside) {
        
        //resuming the layout
        Ext.resumeLayouts(true);
        
        //setting axistitle and fontsize
        var chart = this.getChart(),
            axis;
        
        if (axisside === "left") {
            axis = chart.axes.get(0);
        } else if (axisside === "right") {
            axis = chart.axes.get(1);
        }
        var currenttitle = axis.title;
        
        if (currenttitle === "") {
            axis.setTitle(title);
        } else {
            axis.setTitle(axis.title + " / " + title);
        }
        if (axis.title.length > 80) {
            axis.displaySprite.attr.font = "10px Arial, Helvetica, sans-serif";
        } else if (axis.title.length > 50) {
            axis.displaySprite.attr.font = "12px Arial, Helvetica, sans-serif";
        } else if (axis.title.length > 40) {
            axis.displaySprite.attr.font = "13px Arial, Helvetica, sans-serif";
        }  else  {
            axis.displaySprite.attr.font = "14px Arial, Helvetica, sans-serif";
        }
        
        
        //adding linked yfield to axis fields
        axis.fields.push(yfield);
        
        var series = {
                type : 'line',
                axis : axisside,
                xField : 'TIMESTAMP',
                yField : yfield,
                title: title,
                showInLegend: true,
                smooth: 0,
                highlight: true,
                fill: fill,
                style: {
                    fill: color,
                    stroke: '#808080',
                    'stroke-width': 2
                },
                markerConfig: {
                    type: 'circle',
                    size: 3,
                    radius: 3,
                    stroke: color
                },
                tips : {
                    trackMouse : true,
                    mouseOffset: [1,1],
                    showDelay: 1000,
                    width : 280,
                    height : 50,
                    renderer : function(storeItem, item) {
                        this.setTitle(' Value: : ' + storeItem.get(yfield) + 
                                '<br> Time: ' + storeItem.get('TIMESTAMP'));
                    }
                }
            };
        return series;
    },
    
    /**
     * Setup the renderer for displaying values in chart with mouse hover
     */
    setSeriesRenderer: function(value) {
        
        var renderer = function (storeItem, item) {
            this.setTitle(' ' + value + ' : ' + storeItem.get(value) + 
                    '<br> Time: ' + storeItem.get('TIMESTAMP'));
        };
        
        return renderer;
    },
    
    /**
     * 
     */
    generalizeChartData: function(generalizationfactor, index) {

        var store = this.getChart().getStore();
        
        this.factorpositive = 1 + (generalizationfactor / 100),
            this.factornegative = 1 - (generalizationfactor / 100),
            this.lastValue = null,
            this.lastItem = null,
            this.recsToRemove = [];
        
        Ext.each(store.data.items, function(item) {
            
                var value;
                if (index === 0) {
                    value = item.get('VALUE');
                } else {
                    value = item.get('VALUE' + index);
                }
                var one = this.lastValue / 100;
                var diff = value / one / 100;
                if (diff > this.factorpositive || diff < this.factornegative) {
                    if (this.lastItem) {
                        if (index === 0) {
                            this.lastItem.set('VALUE', this.lastValue);
                        } else {
                            this.lastItem.set('VALUE' + index, this.lastValue);
                        }
                    }
                    this.lastValue = value;
                    this.lastItem = item;
                } else {
                    //keep last record
                    if (store.last() !== item) {
                        if (index === 0) {
                            item.set('VALUE', '');
                        } else {
                            item.set('VALUE' + index, '');
                        }
                    }
                    this.lastValue = value;
                    this.lastItem = item;
                }
        }, this);
        
    },
    
    /**
     * reset the form fields e.g. when loading a new chart
     */
    resetFormFields: function() {
        
        var fieldset =  this.getChartformpanel().down('fieldset[name=axesfieldset]');
        fieldset.removeAll();
        this.getLinechartpanel().createNewYAxis();
        
        Ext.ComponentQuery.query('radiofield[name=rb]')[0].setValue(true);
        Ext.ComponentQuery.query('datefield[name=starttimepicker]')[0].reset();
        Ext.ComponentQuery.query('datefield[name=endtimepicker]')[0].reset();
        Ext.ComponentQuery.query('radiofield[name=generalization]')[1].setValue(true);
        
        Ext.ComponentQuery.query('numberfield[name=leftaxisminimum]')[0].reset();
        Ext.ComponentQuery.query('numberfield[name=leftaxismaximum]')[0].reset();
        Ext.ComponentQuery.query('numberfield[name=rightaxisminimum]')[0].reset();
        Ext.ComponentQuery.query('numberfield[name=rightaxismaximum]')[0].reset();
        
        Ext.ComponentQuery.query('radiogroup[name=leftaxisconfiguration]')[0].items.items[0].setValue(true);
        Ext.ComponentQuery.query('radiogroup[name=rightaxisconfiguration]')[0].items.items[0].setValue(true);
    
    },
    
    /**
     * jump one step back / forward in timerange
     */
    stepchange: function(btn) {
        var me = this;
        
        //reset y-axis max
        me.maxYValue = 0;
        me.minYValue = 9999999;
        me.maxY2Value = 0;
        me.minY2Value = 9999999;
        
        var starttime = me.getStarttimepicker().getValue(),
            endtime = me.getEndtimepicker().getValue(),
            dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0];
        
        if(!Ext.isEmpty(starttime) && !Ext.isEmpty(endtime)) {
            var timediff = Ext.Date.getElapsed(starttime, endtime);
            if(btn.name === "stepback") {
                if (dynamicradio.getValue().rb === "month") {
                    me.getEndtimepicker().setValue(Ext.Date.getLastDateOfMonth(Ext.Date.add(endtime, Ext.Date.MONTH, -1)));
                    me.getStarttimepicker().setValue(Ext.Date.add(starttime, Ext.Date.MONTH, -1));
                } else {
                    me.getEndtimepicker().setValue(starttime);
                    var newstarttime = Ext.Date.add(starttime, Ext.Date.MILLI, -timediff);
                    me.getStarttimepicker().setValue(newstarttime);
                }
                me.requestChartData(true);
            } else if (btn.name === "stepforward") {
                if (dynamicradio.getValue().rb === "month") {
                    me.getEndtimepicker().setValue(Ext.Date.getLastDateOfMonth(Ext.Date.add(endtime, Ext.Date.MONTH, +1)));
                    me.getStarttimepicker().setValue(Ext.Date.add(starttime, Ext.Date.MONTH, +1));
                } else {
                    me.getStarttimepicker().setValue(endtime);
                    var newendtime = Ext.Date.add(endtime, Ext.Date.MILLI, timediff);
                    me.getEndtimepicker().setValue(newendtime);
                }
                me.requestChartData(true);
            }
        }
            
    },
    
    
    /**
     * save the current chart to database
     */
    saveChartData: function() {
        
        var me = this;
        
        //get available foldernames
//        var rootNode = me.getMaintreepanel().getRootNode(),
//            folderArray = [];
//        rootNode.cascadeBy(function(node) {
//           if (node.get('leaf') === false) {
//               if (node.get('text') !== 'root') {
//                   folderArray.push(node.get('text'));
//               }
//           }
//        });
//        console.log(folderArray);
        
        Ext.Msg.prompt("Select a name", "Enter a name to save the Chart", function(action, savename) {
            if (action === "ok" && !Ext.isEmpty(savename)) {
                //replacing spaces in name
                savename = savename.replace(/ /g, "_");
                //replacing + in name
                savename = savename.replace(/\+/g, "_");
                
                //getting the necessary values
                var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]');
                var yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]');
                var yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]');
                var yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]');
                var yaxesstepchecks = Ext.ComponentQuery.query('checkbox[name=yaxisstepcheck]');
                var axissideradio = Ext.ComponentQuery.query('radiogroup[name=axisside]');
                var yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]');
                
                var basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]');
                var basesend = Ext.ComponentQuery.query('numberfield[name=baseend]');
                var basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]');
                var basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
                    
                var starttime = me.getStarttimepicker().getValue(),
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
                    endtime = me.getEndtimepicker().getValue(),
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
                    dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
                    generalization = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
                    generalizationfactor = Ext.ComponentQuery.query('combobox[name=genfactor]')[0].getValue(),
                    leftaxisconfiguration = Ext.ComponentQuery.query('radiogroup[name=leftaxisconfiguration]')[0].getChecked()[0].inputValue,
                    rightaxisconfiguration = Ext.ComponentQuery.query('radiogroup[name=rightaxisconfiguration]')[0].getChecked()[0].inputValue,
                    chart = me.getChart(),
                    store = chart.getStore();
                
                //setting the start / endtime parameter in the chartconfig to the string of the radiofield, gets parsed on load
                if (this.getStarttimepicker().isDisabled()) {
                    dynamicradio.eachBox(function(box, idx) {
                        if (box.checked) {
                            dbstarttime = box.inputValue;
                            dbendtime = box.inputValue;
                        }
                    });
                }
                
                var jsonConfig = '{';
                var i = 0;
                Ext.each(devices, function(dev) {
                    
                    var device = dev.getValue(),
                        yaxis = yaxes[i].getValue(),
                        yaxiscolorcombo = yaxescolorcombos[i].getDisplayValue(),
                        yaxisfillcheck = yaxesfillchecks[i].checked,
                        yaxisstepcheck = yaxesstepchecks[i].checked,
                        axisside = axissideradio[i].getChecked()[0].getSubmitValue();
                        yaxisstatistics = yaxesstatistics[i].getValue();
                    
                    if (i === 0) {
                        jsonConfig += '"y":"' + yaxis + '","device":"' + device + '",';
                        jsonConfig += '"yaxiscolorcombo":"' + yaxiscolorcombo + '","yaxisfillcheck":"' + yaxisfillcheck + '",';
                        jsonConfig += '"yaxisstepcheck":"' + yaxisstepcheck + '",';
                        jsonConfig += '"yaxisside":"' + axisside + '",';
                        
                        if (yaxisstatistics !== "none") {
                            jsonConfig += '"yaxisstatistics":"' + yaxisstatistics + '",';
                        }
                    } else {
                        var axisname = "y" + (i + 1) + "axis",
                            devicename = "y" + (i + 1) + "device",
                            colorname = "y" + (i + 1) + "axiscolorcombo",
                            fillname = "y" + (i + 1) + "axisfillcheck",
                            stepname = "y" + (i + 1) + "axisstepcheck",
                            sidename = "y" + (i + 1) + "axisside",
                            statsname = "y" + (i + 1) + "axisstatistics";
                        
                        jsonConfig += '"' + axisname + '":"' + yaxis + '","' + devicename + '":"' + device + '",';
                        jsonConfig += '"' + colorname + '":"' + yaxiscolorcombo + '","' + fillname + '":"' + yaxisfillcheck + '",';
                        jsonConfig += '"' + stepname + '":"' + yaxisstepcheck + '",';
                        jsonConfig += '"' + sidename + '":"' + axisside + '",';
                        if (yaxisstatistics !== "none") {
                            jsonConfig += '"' + statsname + '":"' + yaxisstatistics + '",';
                        }
                    }
                    i++;
                });
                
                if(generalization.checked) {
                    jsonConfig += '"generalization":"true",';
                    jsonConfig += '"generalizationfactor":"' + generalizationfactor + '",';
                }
                
                if (leftaxisconfiguration === 'manual') {
                    var leftaxismin = Ext.ComponentQuery.query('numberfield[name=leftaxisminimum]')[0].getValue(),
                        leftaxismax = Ext.ComponentQuery.query('numberfield[name=leftaxismaximum]')[0].getValue();
                
                    if (Ext.isNumeric(leftaxismin) && Ext.isNumeric(leftaxismax)) {
                        jsonConfig += '"leftaxismin":"' + leftaxismin + '",';
                        jsonConfig += '"leftaxismax":"' + leftaxismax + '",';
                    } else {
                        Ext.Msg.alert("Error", "Left axis configuration is invalid, values will not be saved!");
                    }
                }
                
                if (rightaxisconfiguration === "manual") {
                    var rightaxismin = Ext.ComponentQuery.query('numberfield[name=rightaxisminimum]')[0].getValue(),
                        rightaxismax = Ext.ComponentQuery.query('numberfield[name=rightaxismaximum]')[0].getValue();
                    
                    if (Ext.isNumeric(rightaxismin) && Ext.isNumeric(rightaxismax)) {
                        jsonConfig += '"rightaxismin":"' + rightaxismin + '",';
                        jsonConfig += '"rightaxismax":"' + rightaxismax + '",';
                    } else {
                        Ext.Msg.alert("Error", "Right axis configuration is invalid, values will not be saved!");
                    }
                }
                
                var j = 0;
                Ext.each(basesstart, function(base) {
                    var basestart = basesstart[j].getValue(),
                        baseend = basesend[j].getValue(),
                        basecolor = basescolors[j].getDisplayValue(),
                        basefill = basesfills[j].checked;
                    
                    j++;
                    jsonConfig += '"base' + j + 'start":"' + basestart + '","base' + j + 'end":"' + baseend + '",';
                    jsonConfig += '"base' + j + 'color":"' + basecolor + '","base' + j + 'fill":"' + basefill + '",';
                });
                
                jsonConfig += '"starttime":"' + dbstarttime + '","endtime":"' + dbendtime + '"}';
            
                var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                    url +=devices[0].getValue() + '+savechart+""+""+' + savename + '+' + jsonConfig + '&XHR=1'; 
                
                chart.setLoading(true);
                
                Ext.Ajax.request({
                    method: 'POST',
                    disableCaching: false,
                    url: url,
                    success: function(response){
                        chart.setLoading(false);
                        var json = Ext.decode(response.responseText);
                        if (json.success === "true" || json.data && json.data.length === 0) {
                            me.getMaintreepanel().fireEvent("treeupdated");
                            Ext.Msg.alert("Success", "Chart successfully saved!");
                        } else if (json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be saved!");
                        }
                    },
                    failure: function() {
                        chart.setLoading(false);
                        if (json && json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be saved!");
                        }
                    }
                });
            }
        }, this);
        
    },
    
    /**
     * loading saved chart data and trigger the load of the chart
     */
    loadsavedchart: function(treeview, record) {
        var me = this;
        if (record.raw.data && record.raw.data.TYPE && record.raw.data.TYPE === "savedchart") {
            var name = record.raw.data.NAME,
                chartdata = record.raw.data.VALUE;
            
            if (typeof chartdata !== "object") {
                try {
                    chartdata = Ext.decode(chartdata);
                } catch (e) {
                    Ext.Msg.alert("Error", "The Chart could not be loaded! RawChartdata was: <br>" + chartdata);
                }
                
            }
            
            //cleanup the form before loading
            this.resetFormFields();
            
            if (chartdata && !Ext.isEmpty(chartdata)) {
                
                //reset y-axis max
                me.maxYValue = 0;
                me.minYValue = 9999999;
                me.maxY2Value = 0;
                me.minY2Value = 9999999;
                
                //count axes
                var axescount = 0;
                Ext.iterate(chartdata, function(key, value) {
                    if (key.indexOf("device") >= 0 && value != "null") {
                        axescount++;
                    }
                });
                
                var yaxeslength = Ext.ComponentQuery.query('combobox[name=yaxiscombo]').length;
                while (yaxeslength < axescount) {
                    Ext.ComponentQuery.query('linechartpanel')[0].createNewYAxis();
                    yaxeslength++;
                }
                
                var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]');
                var yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]');
                var yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]');
                var yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]');
                var yaxesstepchecks = Ext.ComponentQuery.query('checkbox[name=yaxisstepcheck]');
                var axissideradio = Ext.ComponentQuery.query('radiogroup[name=axisside]');
                var yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]');
                
                var i = 0;
                Ext.each(yaxes, function(yaxis) {
                    if (i === 0) {
                        devices[i].setValue(chartdata.device);
                        yaxes[i].getStore().getProxy().url = url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + chartdata.device + '+getreadings&XHR=1';
                        yaxes[i].setDisabled(false);
                        yaxes[i].setValue(chartdata.y);
                        yaxescolorcombos[i].setValue(chartdata.yaxiscolorcombo);
                        yaxesfillchecks[i].setValue(chartdata.yaxisfillcheck);
                        yaxesstepchecks[i].setValue(chartdata.yaxisstepcheck);
                        axissideradio[i].items.items[0].setValue(chartdata.yaxisside);
                        
                        if (chartdata.yaxisstatistics && chartdata.yaxisstatistics !== "") {
                            yaxesstatistics[i].setValue(chartdata.yaxisstatistics);
                        } else {
                            yaxesstatistics[i].setValue("none");
                        }
                        i++;
                    } else {
                        var axisdevice = "y" + (i + 1) + "device",
                            axisname = "y" + (i + 1) + "axis",
                            axiscolorcombo = axisname + "colorcombo",
                            axisfillcheck = axisname + "fillcheck",
                            axisstepcheck = axisname + "stepcheck",
                            axisside = axisname + "side",
                            axisstatistics = axisname + "statistics";
                            
                        eval('devices[i].setValue(chartdata.' + axisdevice + ')');
                        yaxes[i].getStore().getProxy().url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + eval('chartdata.' + axisdevice) + '+getreadings&XHR=1';
                        yaxes[i].setDisabled(false);
                        eval('yaxes[i].setValue(chartdata.' + axisname + ')');
                        eval('yaxescolorcombos[i].setValue(chartdata.' + axiscolorcombo + ')');
                        eval('yaxesfillchecks[i].setValue(chartdata.' + axisfillcheck + ')');
                        eval('yaxesstepchecks[i].setValue(chartdata.' + axisstepcheck + ')');
                        eval('axissideradio[i].items.items[0].setValue(chartdata.' + axisside + ')');
                        
                        if (eval('chartdata.' + axisstatistics) && eval('chartdata.' + axisstatistics) !== "") {
                            eval('yaxesstatistics[i].setValue(chartdata.' + axisstatistics + ')');
                        } else {
                            yaxesstatistics[i].setValue("none");
                        }
                        i++;
                    }
                });

                //handling baselines
                var basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]'),
                    baselinecount = 0;
                
                Ext.iterate(chartdata, function(key, value) {
                    if (key.indexOf("base") >= 0 && key.indexOf("start") >= 0 && value != "null") {
                        baselinecount++;
                    }
                });
                
                var renderedbaselines = basesstart.length;
                while (renderedbaselines < baselinecount) {
                    Ext.ComponentQuery.query('linechartpanel')[0].createNewBaseLineFields();
                    renderedbaselines++;
                }
                
                i = 0;
                var j = 1;
                    basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]'),
                    basesend = Ext.ComponentQuery.query('numberfield[name=baseend]'),
                    basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]'),
                    basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
                    
                Ext.each(basesstart, function(base) {
                    var start = parseFloat(eval('chartdata.base' + j  + 'start'), 10);
                    var end = parseFloat(eval('chartdata.base' + j  + 'end'), 10);
                    
                    basesstart[i].setValue(start);
                    basesend[i].setValue(end);
                    basescolors[i].setValue(eval('chartdata.base' + j  + 'color'));
                    basesfills[i].setValue(eval('chartdata.base' + j  + 'fill'));
                    i++;
                    j++;
                });
                
                //convert time
                var dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
                    st = chartdata.starttime;
                if (st === "year" || st === "month" || st === "week" || st === "day" || st === "hour") {
                    dynamicradio.eachBox(function(box, idx) {
                        if (box.inputValue === st) {
                            box.setValue(true);
                        }
                    });
                } else {
                    var start = chartdata.starttime.replace("_", " "),
                        end = chartdata.endtime.replace("_", " ");
                    this.getStarttimepicker().setValue(start);
                    this.getEndtimepicker().setValue(end);
                }
                
                var genbox = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
                    genfaccombo = Ext.ComponentQuery.query('combobox[name=genfactor]')[0];
                
                if (chartdata.generalization && chartdata.generalization === "true") {
                    genbox.setValue(true);
                    genfaccombo.setValue(chartdata.generalizationfactor);
                } else {
                    genfaccombo.setValue('30');
                    genbox.setValue(false);
                }
                
                if (chartdata.leftaxismin && chartdata.leftaxismax) {
                    Ext.ComponentQuery.query('radiogroup[name=leftaxisconfiguration]')[0].items.items[1].setValue(true);
                    Ext.ComponentQuery.query('numberfield[name=leftaxisminimum]')[0].setValue(chartdata.leftaxismin);
                    Ext.ComponentQuery.query('numberfield[name=leftaxismaximum]')[0].setValue(chartdata.leftaxismax);
                }
                
                if (chartdata.rightaxismin && chartdata.rightaxismax) {
                    Ext.ComponentQuery.query('radiogroup[name=rightaxisconfiguration]')[0].items.items[1].setValue(true);
                    Ext.ComponentQuery.query('numberfield[name=rightaxisminimum]')[0].setValue(chartdata.rightaxismin);
                    Ext.ComponentQuery.query('numberfield[name=rightaxismaximum]')[0].setValue(chartdata.rightaxismax);
                }
                
                this.requestChartData();
                this.getLinechartpanel().setTitle(name);
            } else {
                Ext.Msg.alert("Error", "The Chart could not be loaded! RawChartdata was: <br>" + chartdata);
            }
            
        }
    },
    
    /**
     * Rename a chart
     */
    renamechart: function(menu, e) {
        var me = this,
            chartid = menu.record.raw.data.ID,
            oldchartname = menu.record.raw.data.NAME;
        
        Ext.Msg.prompt("Renaming Chart", "Enter a new name for this Chart", function(action, savename) {
            if (action === "ok" && !Ext.isEmpty(savename)) {
                //replacing spaces in name
                savename = savename.replace(/ /g, "_");
                //replacing + in name
                savename = savename.replace(/\+/g, "_");
                
                var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+renamechart+""+""+' + savename + '+' + chartid + '&XHR=1'; 
                
                Ext.Ajax.request({
                    method: 'GET',
                    disableCaching: false,
                    url: url,
                    success: function(response){
                        var json = Ext.decode(response.responseText);
                        if (json && json.success === "true" || json.data && json.data.length === 0) {
                            me.getMaintreepanel().fireEvent("treeupdated");
                            Ext.Msg.alert("Success", "Chart successfully renamed!");
                        } else if (json && json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be renamed, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be renamed!");
                        }
                    },
                    failure: function() {
                        if (json && json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be renamed, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be renamed!");
                        }
                    }
                });
                
            }
        });
    },
    
    /**
     * Delete a chart by its id from the database
     */
    deletechart: function(menu, e) {
        var me = this,
            chartid = menu.record.raw.data.ID;
        
        if (Ext.isDefined(chartid) && chartid !== "") {
            
            Ext.create('Ext.window.Window', {
                width: 250,
                layout: 'fit',
                title:'Delete?',
                modal: true,
                items: [
                    {
                        xtype: 'displayfield',
                        value: 'Do you really want to delete this chart?'
                    }
                ],  
                buttons: [{ 
                    text: "Ok", 
                    handler: function(btn){ 
                        
                        var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+deletechart+""+""+' + chartid + '&XHR=1'; 
                    
                        Ext.Ajax.request({
                            method: 'GET',
                            disableCaching: false,
                            url: url,
                            success: function(response){
                                var json = Ext.decode(response.responseText);
                                if (json && json.success === "true" || json.data && json.data.length === 0) {
                                    var rootNode = me.getMaintreepanel().getRootNode();
                                    var deletedNode = rootNode.findChildBy(function(rec) {
                                        if (rec.raw.data && rec.raw.data.ID === chartid) {
                                            return true;
                                        }
                                    }, this, true);
                                    if (deletedNode) {
                                        deletedNode.destroy();
                                    }
                                    Ext.Msg.alert("Success", "Chart successfully deleted!");
                                    
                                } else if (json && json.msg) {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted, error Message is:<br><br>" + json.msg);
                                } else {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted!");
                                }
                                btn.up().up().destroy();
                            },
                            failure: function() {
                                if (json && json.msg) {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted, error Message is:<br><br>" + json.msg);
                                } else {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted!");
                                }
                                btn.up().up().destroy();
                            }
                        });
                    }
                },
                {
                    text: "Cancel",
                    handler: function(btn){
                        btn.up().up().destroy();
                    }
                }]
            }).show();
        } else {
            Ext.Msg.alert("Error", "The Chart could not be deleted, no record id has been found");
        }
            
    },
    
    /**
     * fill the charts grid with data
     */
    fillChartGrid: function(jsondata, valuetext) {
        if (jsondata && jsondata[0]) {
            //this.getChartformpanel().collapse();
            
            var store = this.getChartdatagrid().getStore(),
                columnwidth = 0,
                storefields = [],
                gridcolumns = [];
            
            if (store.model.fields && store.model.fields.length > 0) {
                Ext.each(store.model.getFields(), function(field) {
                    storefields.push(field.name);
                });
            }
            var i = 0;
            Ext.each(jsondata, function(dataset) {
                Ext.iterate(dataset, function(key, value) {
                    
                    if (!Ext.Array.contains(storefields, key)) {
                        storefields.push(key);
                    }
                });
                // we add each dataset a new key for the valuetext
                jsondata[i].valuetext = valuetext;
                i++;
            });
            store.model.setFields(storefields);
            
            columnwidth = 99 / storefields.length + "%";
            
            Ext.each(storefields, function(key) {
                var column;
                if (key != "TIMESTAMP") {
                    column = { 
                        header: key,
                        dataIndex: key, 
//                        xtype: 'numbercolumn',
//                        format:'0.000',
//                        renderer: function(value){
//                            return parseFloat(value, 10);
//                        },
                        width: columnwidth
                    };
                } else {
                    column = { 
                        header: key,
                        dataIndex: key, 
                        width: columnwidth
                    };
                }
                
                gridcolumns.push(column);
            });
            
            this.getChartdatagrid().reconfigure(store, gridcolumns);
            store.add(jsondata);
        }
        
    },
    
    /**
     * highlight hoverered record from grid in chart
     */
    highlightRecordInChart: function(gridview, record) {

        var recdate = new Date(Ext.Date.parse(record.get("TIMESTAMP"), 'Y-m-d H:i:s')),
            chartstore = this.getChart().getStore(),
            chartrecord,
            found = false,
            highlightSprite;
        
        chartstore.each(function(rec) {
            if (Ext.Date.isEqual(new Date(rec.get("TIMESTAMP")), recdate)) {
                var valuematcher = record.raw.valuetext,
                    gridvaluematcher = valuematcher.replace(/[0-9]/g, '');
                var chartrec = rec.get(valuematcher);
                var gridrec = record.get(gridvaluematcher);
                if (parseInt(chartrec, 10) === parseInt(gridrec, 10)) {
                    chartrecord = rec;
                    return false;
                }
            }
        });
        
        if (chartrecord && !Ext.isEmpty(chartrecord)) {
            Ext.each(this.getChart().series.items, function(serie) {
                Ext.each(serie.items, function(sprite) {
                    if (sprite.storeItem === chartrecord) {
                        highlightSprite = sprite;
                        found = true;
                    }
                    if (found) {
                        return;
                    }
                });
                if (found) {
                    return;
                }
            });
            if (highlightSprite && !Ext.isEmpty(highlightSprite)) {
                highlightSprite.sprite.attr.radius = 10;
                this.getChart().redraw();
            }
        }
    },
    
    /**
     * handling the moving of nodes in tree, saving new position of saved charts in db
     */
    movenodeintree: function(treeview, action, collidatingrecord) {
        var unsorted = Ext.ComponentQuery.query('treepanel button[name=unsortedtree]')[0].pressed;
        
        //only save orders when in sorted mode
        if (!unsorted) {
            var rec = action.records[0],
            id = rec.raw.data.ID;
        
            if (rec.raw.data && rec.raw.data.ID && rec.raw.data.TYPE === "savedchart") {
                var rootNode = this.getMaintreepanel().getRootNode();
                rootNode.cascadeBy(function(node) {
                    if (node.raw && node.raw.data && node.raw.data.ID && node.raw.data.ID === id) {
                        //updating whole folder to get indexes right
                        Ext.each(node.parentNode.childNodes, function(node) {
                            var ownerfolder = node.parentNode.data.text,
                            index = node.parentNode.indexOf(node);
                            
                
                            if (node.raw.data && node.raw.data.ID && node.raw.data.VALUE) {
                                var chartid = node.raw.data.ID,
                                    chartconfig = node.raw.data.VALUE;
                                chartconfig.parentFolder = ownerfolder;
                                chartconfig.treeIndex = index;
                                var encodedchartconfig = Ext.encode(chartconfig),
                                    url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+updatechart+""+""+' + chartid + '+' + encodedchartconfig + '&XHR=1'; 
                                
                                Ext.Ajax.request({
                                    method: 'GET',
                                    disableCaching: false,
                                    url: url,
                                    success: function(response){
                                        var json = Ext.decode(response.responseText);
                                        if (json && json.success === "true" || json.data && json.data.length === 0) {
                                            //be quiet
                                        } else if (json && json.msg) {
                                            Ext.Msg.alert("Error", "The new position could not be saved, error Message is:<br><br>" + json.msg);
                                        } else {
                                            Ext.Msg.alert("Error", "The new position could not be saved!");
                                        }
                                    },
                                    failure: function() {
                                        if (json && json.msg) {
                                            Ext.Msg.alert("Error", "The new position could not be saved, error Message is:<br><br>" + json.msg);
                                        } else {
                                            Ext.Msg.alert("Error", "The new position could not be saved!");
                                        }
                                    }
                                });
                            }
                            
                        });
                    }
                });
            }
        
        }
    }
});