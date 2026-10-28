; программа на ассемблере для Windows x64
; запрашивает у пользователя ввод строки, сохраняет её в файл output.txt в кодировке UTF-16LE с BOM
; способ запуска и сборки через терминал:
;
; nasm -f win64 programme.asm -o programme.obj
; .\GoLink /console /entry:main /fo=programme.exe programme.obj kernel32.dll
; .\programme.exe
;

bits 64
default rel

%define STD_OUTPUT_HANDLE -11
%define STD_INPUT_HANDLE -10

extern GetLastError
extern GetStdHandle
extern WriteConsoleW
extern ReadConsoleW
extern CreateFileA
extern WriteFile
extern CloseHandle
extern ExitProcess

section .data
    prompt:
        dw 0x0412, 0x0432, 0x0435, 0x0434, 0x0438, 0x0442, 0x0435         ; "Введите"
        dw 0x0020                                                         ; " "
        dw 0x0441, 0x0442, 0x0440, 0x043E, 0x043A, 0x0443                 ; "строку"
        dw 0x0020, 0x003A, 0x0020                                         ; " : "
    prompt_chars equ ($ - prompt) / 2

    file_name db "output.txt", 0
    utf16_bom  db 0xFF, 0xFE

section .bss
    align 8
    stdin_handle  resq 1
    stdout_handle resq 1
    file_handle   resq 1

    chars_read    resd 1
    bytes_written resd 1

    align 2
    input_buffer  resw 256

section .text
    global main

main:
    
    ; порядок передачи аргументов в Windows x64 ABI:
    ; rcx - 1-й аргумент
    ; rdx - 2-й аргумент
    ; r8  - 3-й аргумент
    ; r9  - 4-й аргумент
    ; дальше через стек (push)

    sub rsp, 72

    ; ------ получаем дескриптор стандартного потока вывода < начало кода > ------

    ; функция получения дескриптора стандартного потока вывода в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: - 
    ; результат возвращается в stdout_handle
    GetStdOUTHandle:
        
        ; Получить stdout.
        mov ecx, STD_OUTPUT_HANDLE                    
        call GetStdHandle
        test rax, rax
        jz .fail
        cmp rax, -1
        je .fail
        mov [stdout_handle], rax
        jmp WriteTextInConsole

        .fail:
            mov ecx, 1                      ; код завершения 1
            call ExitProcess
            

    ; ------ получаем дескриптор стандартного потока вывода < конец кода > ------




    ; ------ печатаем строку в терминал < начало кода > ------

    WriteTextInConsole:
        mov rcx, [stdout_handle]
        lea rdx, [prompt]
        mov r8d, prompt_chars
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteConsoleW
        test eax, eax
        jz .fail
        jmp GetStdINHandle

        .fail:
            mov ecx, 2                      ; код завершения 2
            call ExitProcess

    ; ------ печатаем строку в терминал < конец кода > ------




    ; ------ получаем дескриптор стандартного потока ввода < начало кода > ------
    
    ; функция получения дескриптора стандартного потока ввода в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: -
    ; результат возвращается в stdin_handle
    GetStdINHandle:
        mov ecx, STD_INPUT_HANDLE                    
        call GetStdHandle
        test rax, rax
        jz .fail
        cmp rax, -1
        je .fail
        mov [stdin_handle], rax
        jmp ReadTextFromConsole

        .fail:
            mov ecx, 3                      ; код завершения 3
            call ExitProcess

    ; ------ получаем дескриптор стандартного потока ввода < конец кода > ------




    ; ------ читаем строку из терминала < начало кода > ------

    ; функция чтения строки из терминала в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: -
    ; результат возвращается в input_buffer и chars_read
    ; input_buffer - буфер для хранения введённой строки, chars_read - количество считанных символов
    ReadTextFromConsole:
        mov rcx, [stdin_handle]
        lea rdx, [input_buffer]
        mov r8d, 255
        lea r9, [chars_read]
        mov qword [rsp + 32], 0
        call ReadConsoleW
        test eax, eax
        jz .fail
        jmp trim_done

        .fail:
            mov ecx, 4                      ; код завершения 4
            call ExitProcess

    ; ------ читаем строку из терминала < конец кода > ------



    trim_done:
    ; Открыть существующий файл или создать новый.
    lea rcx, [file_name]
    mov edx, 0x00000004             ; FILE_APPEND_DATA
    xor r8d, r8d                     ; dwShareMode = 0
    xor r9d, r9d                     ; lpSecurityAttributes = NULL
    mov dword [rsp + 32], 4          ; OPEN_ALWAYS
    mov dword [rsp + 40], 0x80       ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 48], 0          ; hTemplateFile = NULL
    call CreateFileA

    cmp rax, -1                      ; INVALID_HANDLE_VALUE
    je fail
    mov [file_handle], rax

    ; ERROR_ALREADY_EXISTS = 183: файл уже был, BOM добавлять не нужно.
    call GetLastError
    cmp eax, 183
    je .append_text

    ; Файл только что создан — записать BOM UTF-16LE.
    mov rcx, [file_handle]
    lea rdx, [utf16_bom]
    mov r8d, 2
    lea r9, [bytes_written]
    mov qword [rsp + 32], 0
    call WriteFile
    test eax, eax
    jz .close_fail

.append_text:
    ; Дописать введённую строку в конец файла.
    mov eax, [chars_read]
    shl eax, 1                       ; UTF-16: 2 байта на единицу
    mov r8d, eax

    mov rcx, [file_handle]
    lea rdx, [input_buffer]
    lea r9, [bytes_written]
    mov qword [rsp + 32], 0
    call WriteFile
    test eax, eax
    jz .close_fail

    mov rcx, [file_handle]
    call CloseHandle

    xor ecx, ecx                     ; код завершения 0
    call ExitProcess

.close_fail:
    mov rcx, [file_handle]
    call CloseHandle
    jmp fail

    fail:
        mov ecx, 1                      ; код завершения 1
        call ExitProcess