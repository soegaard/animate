from pathlib import Path
import sys,re,json
root=Path(sys.argv[1]); errors=[]; forms={}
for f in sorted(root.rglob('*.rkt')):
 s=f.read_text(); stack=[]; i=0; line=1; col=1
 while i<len(s):
  c=s[i]
  if c=='\n': line+=1; col=1;i+=1;continue
  if c==';':
   e=s.find('\n',i);i=len(s) if e<0 else e;continue
  if s.startswith('#|',i):
   depth=1;i+=2
   while i<len(s) and depth:
    if s.startswith('#|',i):depth+=1;i+=2
    elif s.startswith('|#',i):depth-=1;i+=2
    else:line+=s[i]=='\n';i+=1
   continue
  if c=='"':
   start=line;i+=1
   while i<len(s):
    if s[i]=='\\':
     # Detect illegal escapes accepted by neither Racket strings nor regex
     if i+1<len(s) and s[i+1] not in 'abtnvfre\\\"\'\n\r01234567xuU':errors.append((str(f.relative_to(root)),line,'unknown string escape '+repr(s[i:i+2])))
     i+=2
    elif s[i]=='"': i+=1;break
    else:line+=s[i]=='\n';i+=1
   else:errors.append((str(f.relative_to(root)),start,'unterminated string'))
   continue
  if s.startswith('#\\',i):
   i+=2
   if i<len(s):
    if s[i] in '()[]{};"':i+=1
    else:
     while i<len(s) and not s[i].isspace() and s[i] not in '()[]{}':i+=1
   continue
  if c in '([{':stack.append((c,line))
  elif c in ')]}':
   if not stack: errors.append((str(f.relative_to(root)),line,'unexpected '+c)); break
   a,l=stack.pop()
   if {'(':')','[':']','{':'}'}[a]!=c:errors.append((str(f.relative_to(root)),line,f'mismatched {c}; {a} opened line {l}'));break
  i+=1;col+=1
 else:
  for c,l in stack:errors.append((str(f.relative_to(root)),l,'unclosed '+c))
print(json.dumps({'files':len(list(root.rglob('*.rkt'))),'errors':errors},indent=2))
sys.exit(bool(errors))
