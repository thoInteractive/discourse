hljs.registerLanguage("angelscript",function(e){var i={cN:"built_in",b:"\\b(void|bool|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|string|ref|array|double|float|auto|dictionary)"},t={cN:"symbol",b:"[a-zA-Z0-9_]+@"},n={cN:"keyword",b:"<",e:">",c:[i,t]};return i.c=[n],t.c=[n],{aliases:["asc"],k:"for in|0 break continue while do|0 return if else case switch namespace is cast or and xor not get|0 in inout|10 out override set|0 private public const default|0 final shared external mixin|10 enum typedef funcdef this super import from interface abstract|0 try catch protected explicit",i:"(^using\\s+[A-Za-z0-9_\\.]+;$|\\bfunctions*[^\\(])",c:[{cN:"string",b:"'",e:"'",i:"\\n",c:[e.BE],r:0},{cN:"string",b:'"',e:'"',i:"\\n",c:[e.BE],r:0},{cN:"string",b:'"""',e:'"""'},e.CLCM,e.CBCM,{bK:"interface namespace",e:"{",i:"[;.\\-]",c:[{cN:"symbol",b:"[a-zA-Z0-9_]+"}]},{bK:"class",e:"{",i:"[;.\\-]",c:[{cN:"symbol",b:"[a-zA-Z0-9_]+",c:[{b:"[:,]\\s*",c:[{cN:"symbol",b:"[a-zA-Z0-9_]+"}]}]}]},i,t,{cN:"literal",b:"\\b(null|true|false)"},{cN:"number",b:"(-?)(\\b0[xX][a-fA-F0-9]+|(\\b\\d+(\\.\\d*)?f?|\\.\\d+f?)([eE][-+]?\\d+f?)?)"}]}});