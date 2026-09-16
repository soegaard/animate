"""Source-shape checks only. This is NOT Racket expansion or execution."""
import re,sys,json
from pathlib import Path
class Atom(str):pass
class Str(str):pass
class L(list):
 def __init__(self,items=(),line=0): super().__init__(items); self.line=line

def tokenize(text):
 i=0;line=1
 while i<len(text):
  c=text[i]
  if c.isspace():line+=c=='\n';i+=1;continue
  if text.startswith('#lang',i) or c==';':
   end=text.find('\n',i);i=end if end>=0 else len(text);continue
  if text.startswith('#|',i):
   d=1;i+=2
   while d:
    if text.startswith('#|',i):d+=1;i+=2
    elif text.startswith('|#',i):d-=1;i+=2
    else:line+=text[i]=='\n';i+=1
   continue
  st=line
  if c=='"' or text.startswith('#"',i) or text.startswith('#rx"',i) or text.startswith('#px"',i):
   i=text.index('"',i)+1;buf=''
   while text[i]!='"':
    if text[i]=='\\':buf+=text[i:i+2];i+=2
    else:buf+=text[i];line+=text[i]=='\n';i+=1
   i+=1;yield Str(buf),st;continue
  if text.startswith('#\\',i):
   start=i;i+=2
   if text[i] in '()[]{};"':i+=1
   else:
    while i<len(text) and not text[i].isspace() and text[i] not in '()[]{}':i+=1
   yield Atom(text[start:i]),st;continue
  if text.startswith('#,@',i):yield Atom('#,@'),st;i+=3;continue
  if text.startswith('#`',i) or text.startswith("#'",i) or text.startswith('#,',i) or text.startswith(',@',i):
   yield Atom(text[i:i+2]),st;i+=2;continue
  if c in "()[]{}'`,":yield Atom(c),st;i+=1;continue
  start=i
  while i<len(text) and not text[i].isspace() and text[i] not in "()[]{}'`,;\"":i+=1
  if i==start:raise ValueError((i,text[i:i+20]))
  yield Atom(text[start:i]),st

def parse(text):
 ts=list(tokenize(text));idx=0
 def read():
  nonlocal idx
  t,line=ts[idx];idx+=1
  if t in ['(','[','{']:
   contents=L(line=line)
   while ts[idx][0] not in [')',']','}']:contents.append(read())
   idx+=1;return contents
  if t in ["'",'`',',',',@',"#'",'#`','#,','#,@']:
   return L([Atom({'\'':'quote','`':'quasiquote',',':'unquote',',@':'unquote-splicing',"#'":'syntax','#`':'quasisyntax','#,':'unsyntax','#,@':'unsyntax-splicing'}[t]),read()],line)
  return t
 result=[]
 while idx<len(ts):result.append(read())
 return result

def walk(x):
 if isinstance(x,list):
  yield x
  if x and x[0] in ['quote','syntax']:return
  if x and x[0]=='struct-copy':
   for field in x[3:]:
    if isinstance(field,list):
     for value in field[1:]:yield from walk(value)
   return
  for i in x:yield from walk(i)

def head(x):return str(x[0]) if isinstance(x,list) and x else ''
if __name__=='__main__':
 root=Path(sys.argv[1]);trees={};errors=[];summaries=[];structs={}
 for p in root.rglob('*.rkt'):
  try: trees[p]=parse(p.read_text())
  except Exception as e:errors.append([str(p.relative_to(root)),'parse',repr(e)])
 for p,forms in trees.items():
  for f in forms:
   if head(f)=='struct':
    name=f[1];fields=f[2] if isinstance(f[2],list) else f[3]
    inherited=2 if name=='exn:fail:slides' else 0
    structs[str(name)]=len(fields)+inherited
 for p,forms in trees.items():
  # Tests must be one suite in a definition, rather than accidentally escaping
  # to top level after an early parenthesis.
  for f in forms:
   if head(f)=='test-case':errors.append([str(p.relative_to(root)),f.line,'test-case escaped its suite'])
   if head(f)=='define' and len(f)>2 and f[1]=='tests':
    if head(f[2])!='test-suite':errors.append([str(p.relative_to(root)),f.line,'tests is not a suite'])
    else:summaries.append([str(p.relative_to(root)),len([x for x in f[2][2:] if head(x)=='test-case'])])
  for f in forms:
   for x in walk(f):
    h=head(x)
    if h in ['if','set!','define-values'] and len(x)!=({'if':4,'set!':3,'define-values':3}[h]):
     errors.append([str(p.relative_to(root)),x.line,'invalid '+h+' shape'])
    if h=='define' and len(x)>1 and isinstance(x[1],Atom) and len(x)!=3:
     errors.append([str(p.relative_to(root)),x.line,'invalid variable define shape'])
    if h in structs and len(x)-1!=structs[h]:
     # Skip structure declarations, patterns, and provide specs by requiring
     # an actual call-shaped positional application with expected head.
     errors.append([str(p.relative_to(root)),x.line,f'{h}: apparent arity {len(x)-1}, expected {structs[h]}'])
 print(json.dumps({'files':len(trees),'suites':summaries,'errors':errors},indent=2))
