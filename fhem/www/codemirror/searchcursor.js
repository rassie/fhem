(function(g){"object"==typeof exports&&"object"==typeof module?g(require("../../lib/codemirror")):"function"==typeof define&&define.amd?define(["../../lib/codemirror"],g):g(CodeMirror)})(function(g){function r(e,b,c,a){this.atOccurrence=!1;this.doc=e;null==a&&"string"==typeof b&&(a=!1);c=c?e.clipPos(c):k(0,0);this.pos={from:c,to:c};if("string"!=typeof b)b.global||(b=new RegExp(b.source,b.ignoreCase?"ig":"g")),this.matches=function(c,n){if(c){b.lastIndex=0;for(var a=e.getLine(n.line).slice(0,n.ch),
f=0,d,h;;){b.lastIndex=f;f=b.exec(a);if(!f)break;d=f;h=d.index;f=d.index+(d[0].length||1);if(f==a.length)break}(f=d&&d[0].length||0)||(0==h&&0==a.length?d=void 0:h!=e.getLine(n.line).length&&f++)}else b.lastIndex=n.ch,a=e.getLine(n.line),f=(d=b.exec(a))&&d[0].length||0,h=d&&d.index,h+f==a.length||f||(f=1);if(d&&f)return{from:k(n.line,h),to:k(n.line,h+f),match:d}};else{var g=b;a&&(b=b.toLowerCase());var m=a?function(b){return b.toLowerCase()}:function(b){return b},l=b.split("\n");if(1==l.length)this.matches=
b.length?function(c,a){if(c){var q=e.getLine(a.line).slice(0,a.ch),f=m(q),d=f.lastIndexOf(b);if(-1<d)return d=t(q,f,d),{from:k(a.line,d),to:k(a.line,d+g.length)}}else if(q=e.getLine(a.line).slice(a.ch),f=m(q),d=f.indexOf(b),-1<d)return d=t(q,f,d)+a.ch,{from:k(a.line,d),to:k(a.line,d+g.length)}}:function(){};else{var p=g.split("\n");this.matches=function(b,a){var c=l.length-1;if(b){if(!(a.line-(l.length-1)<e.firstLine())&&m(e.getLine(a.line).slice(0,p[c].length))==l[l.length-1]){for(var f=k(a.line,
p[c].length),d=a.line-1,h=c-1;1<=h;--h,--d)if(l[h]!=m(e.getLine(d)))return;var h=e.getLine(d),g=h.length-p[0].length;if(m(h.slice(g))==l[0])return{from:k(d,g),to:f}}}else if(!(a.line+(l.length-1)>e.lastLine())&&(h=e.getLine(a.line),g=h.length-p[0].length,m(h.slice(g))==l[0])){f=k(a.line,g);d=a.line+1;for(h=1;h<c;++h,++d)if(l[h]!=m(e.getLine(d)))return;if(m(e.getLine(d).slice(0,p[c].length))==l[c])return{from:f,to:k(d,p[c].length)}}}}}}function t(e,b,c){if(e.length==b.length)return c;for(b=Math.min(c,
e.length);;){var a=e.slice(0,b).toLowerCase().length;if(a<c)++b;else if(a>c)--b;else return b}}var k=g.Pos;r.prototype={findNext:function(){return this.find(!1)},findPrevious:function(){return this.find(!0)},find:function(e){function b(a){a=k(a,0);c.pos={from:a,to:a};return c.atOccurrence=!1}for(var c=this,a=this.doc.clipPos(e?this.pos.from:this.pos.to);;){if(this.pos=this.matches(e,a))return this.atOccurrence=!0,this.pos.match||!0;if(e){if(!a.line)return b(0);a=k(a.line-1,this.doc.getLine(a.line-
1).length)}else{var g=this.doc.lineCount();if(a.line==g-1)return b(g);a=k(a.line+1,0)}}},from:function(){if(this.atOccurrence)return this.pos.from},to:function(){if(this.atOccurrence)return this.pos.to},replace:function(e,b){if(this.atOccurrence){var c=g.splitLines(e);this.doc.replaceRange(c,this.pos.from,this.pos.to,b);this.pos.to=k(this.pos.from.line+c.length-1,c[c.length-1].length+(1==c.length?this.pos.from.ch:0))}}};g.defineExtension("getSearchCursor",function(e,b,c){return new r(this.doc,e,b,
c)});g.defineDocExtension("getSearchCursor",function(e,b,c){return new r(this,e,b,c)});g.defineExtension("selectMatches",function(e,b){for(var c=[],a=this.getSearchCursor(e,this.getCursor("from"),b);a.findNext()&&!(0<g.cmpPos(a.to(),this.getCursor("to")));)c.push({anchor:a.from(),head:a.to()});c.length&&this.setSelections(c,0)})});