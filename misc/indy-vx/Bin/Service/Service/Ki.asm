	.686p
	.model flat, stdcall
	option casemap :none
	
	include \masm32\include\ntdll.inc
	includelib \masm32\lib\ntdll.lib
	
%NTERR macro
	.if Eax
	Int 3
	.endif
endm

APIERR macro
	.if !Eax
	Int 3
	.endif
endm

.code
	include ..\..\Bin\Gcbe.inc

%ALLOC macro vBase, vSize, vProtect, cSize, Reg32
	mov vBase,NULL
	mov vSize,cSize
	invoke ZwAllocateVirtualMemory, NtCurrentProcess, addr vBase, 0, addr vSize, MEM_COMMIT, PAGE_READWRITE
	mov Reg32,vBase
	%NTERR
	add vBase,cSize - X86_PAGE_SIZE
	mov vSize,X86_PAGE_SIZE
	invoke ZwProtectVirtualMemory, NtCurrentProcess, addr vBase, addr vSize, PAGE_NOACCESS, addr vProtect
	%NTERR	
endm

%FREE macro vBase, vSize
	invoke ZwFreeVirtualMemory, NtCurrentProcess, addr vBase, addr vSize, MEM_RELEASE
endm

$Nt	CHAR "ntoskrnl.exe",0

; +
; ������ ��� ������ IDT.
;
PARSE_CALLBACK_ROUTINE proc Graph:PVOID,	; ������ �� ����.
   GraphEntry:PVOID,	; ������ �� ��������� ����������.
   SubsList:PVOID,	; ������ ���������� ������ �������� � ������� ������.
   SubsCount:ULONG,	; ����� �������� � ������ �������� ������� �����������(NL).
   PreOrPost:BOOLEAN,	; ��� ������.
   pIdt:PULONG
	mov eax,GraphEntry
	test dword ptr [eax + EhEntryType],TYPE_MASK
	jnz Exit
	mov ecx,dword ptr [eax + EhAddress]
	cmp byte ptr [ecx],0B9H	; mov ecx,XXXX
	jne Exit
	mov edx,dword ptr [ecx + 1]
	cmp word ptr [ecx + 5],0A5F3H	; rep movsd
	jne IsShr
	cmp edx,256*8/4
	jne Exit
	jmp Idt
IsShr:
	cmp dword ptr [ecx + 5],0F302E9C1H	; shr ecx,2
	jne Exit
	cmp byte ptr [ecx + 9],0A5H
	jne Exit
	cmp edx,256*8
	jne Exit
Idt:
	mov eax,dword ptr [eax + EhBlink]
	and eax,NOT(TYPE_MASK)
	jz Exit
	test dword ptr [eax + EhEntryType],TYPE_MASK
	jnz Exit
	mov ecx,dword ptr [eax + EhAddress]
	cmp byte ptr [ecx],0BEH
	je @f
	mov eax,dword ptr [eax + EhBlink]
	and eax,NOT(TYPE_MASK)
	jz Exit
	test dword ptr [eax + EhEntryType],TYPE_MASK
	jnz Exit
	mov ecx,dword ptr [eax + EhAddress]
	cmp byte ptr [ecx],0BEH
	jne Exit
@@:
	mov eax,dword ptr [ecx + 1]	; _IDT
	mov edx,pIdt
	mov dword ptr [edx],eax
Exit:
	xor eax,eax
	ret
PARSE_CALLBACK_ROUTINE endp

; +
; ������ ��� ������ kssdoit.
;
PARSE_CALLBACK_ROUTINE2 proc uses ebx Graph:PVOID,	; ������ �� ����.
   GraphEntry:PVOID,	; ������ �� ��������� ����������.
   SubsList:PVOID,	; ������ ���������� ������ �������� � ������� ������.
   SubsCount:ULONG,	; ����� �������� � ������ �������� ������� �����������(NL).
   PreOrPost:BOOLEAN,	; ��� ������.
   Ref:PVOID
	mov edx,GraphEntry
	test dword ptr [edx + EhEntryType],TYPE_MASK
	jnz Exit
	mov eax,dword ptr [edx + EhAddress]
	cmp dword ptr [eax],0D3FFA5F3H
	jne Exit
	
; KiSystemServiceCopyArguments:
; 	F3:A5	rep movs dword ptr es:[edi],dword ptr ds:[esi]
; kssdoit:
; 	FFD3		call ebx

	mov ecx,Ref
	mov dword ptr [ecx],edx
Exit:
	xor eax,eax
	ret
PARSE_CALLBACK_ROUTINE2 endp

_imp__ZwClose proto :HANDLE

; Ebx - ������ �� ������.
;
kssdoit2nd proc C
	.if Eax != dword ptr [_imp__ZwClose + 1]
	   Jmp Ebx
	.endif
	nop
	nop
	nop
	ret
kssdoit2nd endp

xCallStub:
	Call kssdoit2nd
	
Ep proc
Local GpBase:PVOID, GpLimit:PVOID
Local CsBase:PVOID, CsSize:ULONG
Local BiBase:PVOID, BiSize:ULONG
Local GpSize:ULONG, Protect:ULONG
Local Idt:ULONG
Local GpRef:PBLOCK_HEADER
	invoke LoadLibraryEx, addr $Nt, 0, DONT_RESOLVE_DLL_REFERENCES
	mov ebx,eax
	invoke RtlImageNtHeader, Ebx
	%APIERR
	mov esi,eax
	assume esi:PIMAGE_NT_HEADERS
	%ALLOC GpBase, GpSize, Protect, 100H * X86_PAGE_SIZE, Edi
	mov GpLimit,edi
	mov GpBase,edi
	lea ecx,GpLimit
	lea edx,Idt
	mov Idt,eax
	push eax
	push eax
	push edx
	push offset PARSE_CALLBACK_ROUTINE
	mov edx,[esi].OptionalHeader.AddressOfEntryPoint
	push eax
	push eax
	add edx,ebx
	push GCBE_PARSE_SEPARATE
	push ecx
	push edx
	%GPCALL GP_PARSE
	%NTERR
	%FREE GpBase, GpSize
	mov eax,Idt
	%APIERR
	sub eax,[esi].OptionalHeader.ImageBase
	mov eax,dword ptr [eax + ebx + 8*2EH]	; _IDT[46]: KiSystemService()
	sub eax,[esi].OptionalHeader.ImageBase
	lea esi,[eax + ebx]	; *KiSystemService()
	%ALLOC GpBase, GpSize, Protect, 100H * X86_PAGE_SIZE, Edi
	mov GpLimit,edi
	mov GpBase,edi
	lea ecx,GpLimit
	lea edx,GpRef
	mov GpRef,eax
	push eax
	push eax
	push edx
	push offset PARSE_CALLBACK_ROUTINE2
	push eax
	push eax
	push GCBE_PARSE_SEPARATE or GCBE_PARSE_OPENLIST or GCBE_PARSE_IPCOUNTING
	push ecx
	push esi
	%GPCALL GP_PARSE
	%NTERR
	mov esi,GpLimit
	lea ecx,GpLimit
	push eax
	push eax
	push eax
	push eax
	push eax
	push GCBE_PARSE_NL_UNLIMITED
	push GCBE_PARSE_SEPARATE or GCBE_PARSE_OPENLIST or GCBE_PARSE_IPCOUNTING
	push ecx
	push offset kssdoit2nd
	%GPCALL GP_PARSE
	%NTERR
	mov eax,GpRef
	%APIERR
	mov eax,dword ptr [eax + EhFlink]
	and eax,NOT(TYPE_MASK)
	%APIERR
	mov ecx,dword ptr [eax + EhEntryType]
	and ecx,TYPE_MASK
	.if Ecx != HEADER_TYPE_CALL
	   int 3
	.endif
	mov dword ptr [eax + EhBranchLink],esi
	mov dword ptr [eax +  EhAddress],offset xCallStub
	or dword ptr [eax + EhBranchType],BRANCH_DEFINED_FLAG
	or dword ptr [eax + EhDisclosureFlag],DISCLOSURE_CALL_FLAG
	%ALLOC CsBase, CsSize, Protect, 200H * X86_PAGE_SIZE, Esi
	%ALLOC BiBase, BiSize, Protect, 200H * X86_PAGE_SIZE, Edi
	push edi
	push esi
	push GpLimit
	push GpBase
	%GPCALL GP_BUILD_GRAPH
	%NTERR
	%FREE GpBase, GpSize
	; Edi: ISR
	Int 3
	ret
Ep endp
end Ep