// Checks that a directory of .hdll files provides every native required by hlboot.dat
// with the exact signature. Input: natives.txt produced by `HL_DUMP_NATIVES=1 hl hlboot.dat`.
// usage: checknatives <natives.txt> <hdll_dir>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

int main(int argc, char **argv) {
	if( argc < 3 ) { fprintf(stderr,"usage: %s natives.txt hdll_dir\n",argv[0]); return 2; }
	FILE *f = fopen(argv[1],"r");
	if( !f ) { perror("natives"); return 2; }
	char line[1024], curlib[256] = "";
	void *h = NULL;
	int ok = 0, bad = 0;
	while( fgets(line,sizeof(line),f) ) {
		char lib[256], name[256], sig[512];
		if( sscanf(line,"NATIVE %255s %255s %511s",lib,name,sig) != 3 ) continue;
		const char *l = lib[0] == '?' ? lib + 1 : lib;
		if( strcmp(l,curlib) ) {
			char path[1024];
			strcpy(curlib,l);
			if( strcmp(l,"std") == 0 ) snprintf(path,sizeof(path),"%s/libhl.dylib",argv[2]); // std natives live in libhl
			else snprintf(path,sizeof(path),"%s/%s.hdll",argv[2],l);
			h = dlopen(path,RTLD_LAZY);
			if( !h ) printf("LIBFAIL %s: %s\n",path,dlerror());
		}
		if( !h ) { bad++; continue; }
		char sym[300];
		snprintf(sym,sizeof(sym),"hlp_%s",name);
		void *(*p)(const char **) = (void*(*)(const char**))dlsym(h,sym);
		if( !p ) { printf("MISSING %s@%s %s\n",l,name,sig); bad++; continue; }
		const char *s = NULL;
		p(&s);
		if( s ) {
			size_t n = strlen(s);
			if( n && s[n-1] == 'C' ) n--; // HL_CALLB marker
			if( n != strlen(sig) || memcmp(s,sig,n) ) { printf("SIGMISMATCH %s@%s need=%s have=%.*s\n",l,name,sig,(int)n,s); bad++; continue; }
		}
		ok++;
	}
	printf("ok=%d bad=%d\n",ok,bad);
	return bad ? 1 : 0;
}
