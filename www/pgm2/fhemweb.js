/*************** LONGPOLL START **************/
var FW_pollConn;
var FW_curLine; // Number of the next line in FW_pollConn.responseText to parse
var FW_widgets = new Object(); // to be filled by fhemweb_*.js
var FW_leaving;
var isIE = (navigator.appVersion.indexOf("MSIE") > 0);
var isiOS = navigator.userAgent.match(/(iPad|iPhone|iPod)/);


function
log(txt)
{
  if(typeof window.console != "undefined") // IE
    console.log(txt);
}

function
addcsrf(arg)
{
  var csrf = document.body.getAttribute('fwcsrf');
  if(csrf && arg.indexOf('fwcsrf') < 0)
    arg += '&fwcsrf='+csrf;
  return arg;
}

function
FW_cmd(arg)     /* see also FW_devState */
{
  arg = addcsrf(arg);
  var req = new XMLHttpRequest();
  req.open("GET", arg, true);
  req.send(null);
  req.onreadystatechange = function(){
    if(req.readyState == 4)
      FW_errmsg(req.responseText, 5000);
  }
}

function
FW_errmsg(txt, timeout)
{
  var errmsg = document.getElementById("errmsg");
  if(!errmsg) {
    if(txt == "")
      return;
    errmsg = document.createElement('div');
    errmsg.setAttribute("id","errmsg");
    document.body.appendChild(errmsg);
  }
  if(txt == "") {
    document.body.removeChild(errmsg);
    return;
  }
  errmsg.innerHTML = txt;
  if(timeout)
    setTimeout("FW_errmsg('')", timeout);
}

function
FW_doUpdate()
{
  if(FW_pollConn.readyState == 4 && !FW_leaving) {
    FW_errmsg("Connection lost, trying a reconnect every 5 seconds.", 4900);
    setTimeout(FW_longpoll, 5000);
    return; // some problem connecting
  }

  if(FW_pollConn.readyState != 3)
    return;

  var lines = FW_pollConn.responseText.split("\n");
  //Pop the last (maybe empty) line after the last "\n"
  //We wait until it is complete, i.e. terminated by "\n"
  lines.pop();
  var devs = new Array();
  for(var i=FW_curLine; i < lines.length; i++) {
    var l = lines[i];
    log("Longpoll: "+(l.length>132 ? l.substring(0,132)+"...("+l.length+")":l));
    var d = l.split("<<", 3);    // Complete arg

    if(d.length != 3)
      continue;
    var elArr = document.querySelectorAll("[informId='"+d[0]+"']");
    for(var k=0; k<elArr.length; k++){
      el = elArr[k];
      if(el.nodeName.toLowerCase() == "select") {
        // dropdown: set the selected index to the current value
        for(var j=0;j<el.options.length;j++)
          if(el.options[j].value == d[2])
            el.selectedIndex = j;

      } else {
        el.innerHTML=d[2];
        if(d[0].match(/-ts$/))  // timestamps
          el.setAttribute('class', 'changed');

      }
    }

    for(var w in FW_widgets)
      if(FW_widgets[w].updateLine)
        FW_widgets[w].updateLine(d);

    if(d[0].indexOf("-") == -1) // Wont contain -
      devs.push(d[0]);
  }
  //Next time, we continue at the next line
  FW_curLine = lines.length;

  for(var w in FW_widgets) {
    if(FW_widgets[w].updateDevs) {
      FW_widgets[w].updateDevs(devs);
    }
  }

  // reset the connection to avoid memory problems
  if(FW_pollConn.responseText.length > 300*1024)
    FW_longpoll();
}

function
FW_longpoll()
{
  log("Connecting...");
  FW_curLine = 0;
  if(FW_pollConn) {
    FW_leaving = 1;
    FW_pollConn.abort();
  }

  FW_pollConn = new XMLHttpRequest();
  FW_leaving = 0;

  var filter = document.body.getAttribute("longpollfilter");
  if(filter == null)
    filter = "";
  if(filter == "") {
    var embArr = document.getElementsByTagName("embed");
    for(var i = 0; i < embArr.length; i++) {
      var svg = embArr[i].getSVGDocument();
      if(svg &&
         svg.firstChild &&
         svg.firstChild.nextSibling &&
         svg.firstChild.nextSibling.getAttribute("flog"))
        filter=".*";
    }
  }
  if(filter == "") {
    var sa = document.location.search.substring(1).split("&");
    for(var i = 0; i < sa.length; i++) {
      if(sa[i].substring(0,5) == "room=")
        filter=sa[i];
      if(sa[i].substring(0,7) == "detail=")
        filter=sa[i].substring(7);
    }
  }
  if(filter == "" && document.getElementById("floorplan")) { //floorplan special
    var name = document.getElementsByTagName("body")[0].getAttribute("id");
    name = name.substring(0,name.length-5);
    filter=".*;iconPath="+name;
  }
  if(filter == "") {
    var content = document.getElementById("content");
    if(content) {
      var room = content.getAttribute("room");
      if(room)
        filter="room="+room;
    }
  }

  var iP = document.body.getAttribute("iconPath");
  if(iP != null)
    filter = filter +";iconPath="+iP;

  var query = document.location.pathname+"?XHR=1"+
                "&inform=type=status;filter="+filter+
                "&timestamp="+new Date().getTime();
  query = addcsrf(query);
  FW_pollConn.open("GET", query, true);
  FW_pollConn.onreadystatechange = FW_doUpdate;
  FW_pollConn.send(null);
}

function
FW_replaceLinks()
{
  var elArr = document.querySelectorAll("a[href]");
  for(var i1=0; i1< elArr.length; i1++) {
    var a = elArr[i1];
    var ma = a.getAttribute("href").match(/^(.*\?)(cmd[^=]*=.*)$/);
    if(ma == null || ma.length == 0 || !ma[2].match(/=(save|set)/))
      continue;
    a.removeAttribute("href");
    a.setAttribute("onclick", "FW_cmd('"+ma[1]+"XHR=1&"+ma[2]+"')");
    a.setAttribute("style", "cursor:pointer");
  }
}

function
FW_delayedStart()
{
  setTimeout("FW_longpoll()", 100);
  FW_replaceLinks();
}
/*************** LONGPOLL END **************/

/*************** Select **************/
/** Change attr/set argument type to input:text or select **/
function
FW_selChange(sel, list, elName)
{
  var cmd, value;
  var l = list.split(" ");
  for(var i=0; i < l.length; i++) {
    cmd = l[i];
    var off = cmd.indexOf(":");
    if(off >= 0)
      cmd = cmd.substring(0, off);
    if(cmd == sel) {
      if(off >= 0)
        value = l[i].substring(off+1);
      break;
    }
  }
  var el = document.getElementsByName(elName)[0];

  var qFn, qArg;
  var devName="";
  if(elName.indexOf("val.attr")==0) devName = elName.substring(8);
  if(elName.indexOf("val.set") ==0) devName = elName.substring(7);

  var o;
  if(value==undefined) {
    o = new Object();
    o.newEl = document.createElement('input');
    o.newEl.type='text';
    o.newEl.size=30; 
    o.qFn = 'qArg.setAttribute("value", "%")';
    o.qArg = o.newEl;

  } else {
    var vArr = value.split(","); 

    for(var w in FW_widgets) {
      if(FW_widgets[w].selChange) {
        o = FW_widgets[w].selChange(elName, devName, vArr);
        if(o)
          break;
      }
    }

    if(!o) {
      o = new Object();
      o.newEl = document.createElement('select');
      for(var j=0; j < vArr.length; j++) {
        o.newEl.options[j] = new Option(vArr[j], vArr[j]);
      }
      o.qFn = 'FW_querySetSelected(qArg, "%")';
      o.qArg = o.newEl;
    }


  }

  o.newEl.setAttribute('class', el.getAttribute('class'));
  o.newEl.setAttribute('name', elName);
  el.parentNode.replaceChild(o.newEl, el);

  if((typeof o.qFn == "string")) {
    if(elName.indexOf("val.attr")==0)
      FW_queryValue('{AttrVal("'+devName+'","'+sel+'","")}', o.qFn, o.qArg);
    if(elName.indexOf("val.set")==0) {
      qArg = o.qArg;
      eval(o.qFn.replace("%", ""));
      FW_queryValue('{ReadingsVal("'+devName+'","'+sel+'","")}', o.qFn, o.qArg);
    }
  }
}


/*************** Fill attribute **************/
function
FW_queryValue(cmd, qFn, qArg)
{
  var qConn = new XMLHttpRequest();
  qConn.onreadystatechange = function() {
    if(qConn.readyState != 3)
      return;
    var qResp = qConn.responseText.replace(/[\r\n]/g, "")
                                  .replace(/\\/g, "\\\\")
                                  .replace(/"/g, "\\\"");
    eval(qFn.replace("%", qResp));
    delete qConn;
  }
  var query = document.location.pathname+"?cmd="+cmd+"&XHR=1"
  query = addcsrf(query);
  qConn.open("GET", query, true);
  qConn.send(null);
}


function
FW_querySetSelected(el, val)
{
  if(typeof el == 'string')
    el = document.getElementById(el);
  for(var j=0;j<el.options.length;j++)
    if(el.options[j].value == val) {
      el.selectedIndex = j;
      if(el.onchange)
        el.onchange();
      return;
    }
}

//////////////////////////
// start of script functions
function
loadScript(sname, callback)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  var r = h.getAttribute("root");
  if(!r)
    r = "/fhem";
  sname = r+"/"+sname;
  var arr = h.getElementsByTagName("script");
  for(var i1=0; i1<arr.length; i1++)
    if(sname == arr[i1].getAttribute("src")) {
      if(callback)
        callback();
      return;
    }
  var script = document.createElement("script");
  script.src = sname;
  script.async = script.defer = false;
  script.type = "text/javascript";


  log("Loading "+sname);
  if(isIE) {
    script.onreadystatechange = function() {
      if(script.readyState == 'loaded' || script.readyState == 'complete') {
        script.onreadystatechange = null;
        if(callback)
          callback();
      }
    }
  } else {
    if(isiOS) {
      FW_leaving = 1;
      FW_pollConn.abort();
    }
    script.onload = function(){
      if(callback)
        callback();
      if(isiOS)
        FW_longpoll();
    }
  }
  
  h.appendChild(script);
}

function
loadLink(lname)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  var r = h.getAttribute("root");
  if(!r)
    r = "/fhem";
  lname = r+"/"+lname;
  var arr = h.getElementsByTagName("link");
  for(var i1=0; i1<arr.length; i1++)
    if(lname == arr[i1].getAttribute("href"))
      return;
  var link = document.createElement("link");
  link.href = lname;
  link.rel = "stylesheet";
  log("Loading "+lname);
  h.appendChild(link);
}

function
scriptAttribute(sname)
{
  var attr="";
  $("head script").each(function(){
    var src = $(this).attr("src");
    if(src && src.indexOf(sname) >= 0)
      attr = $(this).attr("attr");
  });

  var ua={};
  if(attr && attr != "") {
    try {
      ua=JSON.parse(attr);
    } catch(e){
      FW_errmsg(sname+" Parameter "+e,5000);
    }
  }
  return ua;
}
// end of script functions
//////////////////////////

window.onbeforeunload = function(e)
{ 
  FW_leaving = 1;
  return undefined;
}
