; программа на ассемблере для Windows x64
; запрашивает у пользователя ввод строки, сохраняет её в файл output.txt в кодировке UTF-16LE с BOM
; если такая строка уже есть выводит предупреждение
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
extern GetFileSizeEx
extern SetFilePointerEx
extern ReadFile

section .data
    prompt:
        dw 0x0412, 0x0432, 0x0435, 0x0434, 0x0438, 0x0442, 0x0435         ; "Введите"
        dw 0x0020                                                         ; " "
        dw 0x0441, 0x0442, 0x0440, 0x043E, 0x043A, 0x0443                 ; "строку"
        dw 0x0020, 0x003A, 0x0020                                         ; " : "
    prompt_chars equ ($ - prompt) / 2

    file_name db "output.txt", 0
    utf16_bom  db 0xFF, 0xFE

    file_offset dq 0

    already_message:
        dw 0x0421, 0x0442, 0x0440, 0x043E, 0x043A, 0x0430 ; Строка
        dw 0x0020, 0x0443, 0x0436, 0x0435                 ; " уже"
        dw 0x0020, 0x0435, 0x0441, 0x0442, 0x044C         ; " есть"
        dw 0x0020, 0x0432, 0x0020                         ; " в "
        dw 0x0444, 0x0430, 0x0439, 0x043B, 0x0435         ; "файле"
        dw 0x002E, 0x000D, 0x000A                         ; ".\r\n"
    already_message_chars equ ($ - already_message) / 2

section .bss
    align 8
    stdin_handle  resq 1
    stdout_handle resq 1
    file_handle   resq 1

    chars_read    resd 1
    bytes_written resd 1

    align 2
    input_buffer  resw 256

    file_size       resq 1
    file_bytes_read resd 1
    search_chars    resd 1

    align 2
    search_buffer   resb 1048576

    failure_stage resd 1

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



    ; ------ обрезаем символы перевода строки из конца введённой строки < начало кода > ------

    trim_done:
    mov eax, [chars_read]
    cmp eax, 2
    jb InputTrimmed

    cmp word [input_buffer + rax * 2 - 4], 13
    jne InputTrimmed
    cmp word [input_buffer + rax * 2 - 2], 10
    jne InputTrimmed

    sub eax, 2

    InputTrimmed:
        mov [search_chars], eax

    ; ------ обрезаем символы перевода строки из конца введённой строки < конец кода > ------



    ; ------ открываем или создаём файл < начало кода > ------
    
    ; Функция открытия или создания файла в режиме OPEN_ALWAYS с правом добавления данных в конец в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: file_name
    ; file_name - имя файла, который нужно открыть или создать, пеердается в rcx
    ; результат возвращается в file_handle
        lea rcx, [file_name]
    OpenAnExistingFile:
        mov edx, 0x80000004              ; GENERIC_READ | FILE_APPEND_DATA
        xor r8d, r8d                     ; dwShareMode = 0
        xor r9d, r9d                     ; lpSecurityAttributes = NULL
        mov dword [rsp + 32], 4          ; OPEN_ALWAYS
        mov dword [rsp + 40], 0x80       ; FILE_ATTRIBUTE_NORMAL
        mov qword [rsp + 48], 0          ; hTemplateFile = NULL
        call CreateFileA

        cmp rax, -1                      ; INVALID_HANDLE_VALUE
        je .fail
        mov [file_handle], rax
        jmp CheckingAnErrorCodeToSeeIfAFileExists

        .fail:
            mov ecx, 5                      ; код завершения 5
            call ExitProcess
    
    ; ------ открываем или создаём файл < конец кода > ------



    ; ------ открываем файл и проверяем, есть ли введённая строка в файле < начало кода > ------

    CheckingAnErrorCodeToSeeIfAFileExists:
        ; ERROR_ALREADY_EXISTS = 183: файл уже существовал.
        call GetLastError
        cmp eax, 183
        je CheckStringInFile

        ; Новый файл: сначала записываем BOM UTF-16LE.
        mov rcx, [file_handle]
        lea rdx, [utf16_bom]
        mov r8d, 2
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteFile
        test eax, eax
        jz FileCheckFailed

    CheckStringInFile:
        mov dword [failure_stage], 71
        ; Получить размер файла.
        mov rcx, [file_handle]
        lea rdx, [file_size]
        call GetFileSizeEx
        test eax, eax
        jz FileCheckFailed

        cmp qword [file_size], 1048576
        jbe FileSizeAccepted
        cmp qword [file_size], 1048576
        ja FileCheckFailed

    FileSizeAccepted:
        ; SetFilePointerEx принимает смещение по значению, не адрес.
        mov dword [failure_stage], 73
        mov rcx, [file_handle]
        xor edx, edx                 ; liDistanceToMove = 0
        xor r8d, r8d                 ; lpNewFilePointer = NULL
        xor r9d, r9d                 ; FILE_BEGIN
        call SetFilePointerEx
        test eax, eax
        jz FileCheckFailed

        mov dword [failure_stage], 74
        mov rcx, [file_handle]
        lea rdx, [search_buffer]
        mov r8d, [file_size]
        lea r9, [file_bytes_read]
        mov qword [rsp + 32], 0
        call ReadFile
        test eax, eax
        jz FileCheckFailed

        mov dword [failure_stage], 75
        mov eax, [file_size]
        cmp [file_bytes_read], eax
        jne FileCheckFailed

        ; Убедиться, что прочитан весь файл.
        mov eax, [file_size]
        cmp [file_bytes_read], eax
        jne FileCheckFailed

        ; Пустую строку не считаем найденной.
        mov r8d, [search_chars]
        test r8d, r8d
        jz StringNotFound

        ; Перевести длину файла из байтов в 16-битные символы.
        mov r9d, [file_bytes_read]
        shr r9d, 1

        ; Если строка длиннее файла, совпадения нет.
        cmp r9d, r8d
        jb StringNotFound

        ; r9d = последний допустимый индекс начала совпадения.
        sub r9d, r8d
        xor r10d, r10d              ; индекс начала поиска

    SearchStart:
        cmp r10d, r9d
        ja StringNotFound

        xor r11d, r11d              ; индекс символа во введённой строке

    SearchCharacters:
        cmp r11d, r8d
        jae StringFound

        ; Сравнить очередной UTF-16-символ файла и введённой строки.
        mov eax, r10d
        add eax, r11d
        movzx eax, word [search_buffer + rax * 2]
        cmp ax, word [input_buffer + r11 * 2]
        jne SearchNextStart

        inc r11d
        jmp SearchCharacters

    SearchNextStart:
        inc r10d
        jmp SearchStart

    StringFound:
        ; Сообщить, что строка уже есть в файле.
        mov rcx, [stdout_handle]
        lea rdx, [already_message]
        mov r8d, already_message_chars
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteConsoleW

        mov rcx, [file_handle]
        call CloseHandle

        xor ecx, ecx
        call ExitProcess

    StringNotFound:
        ; Совпадения нет — перейти к существующему коду добавления строки.
        jmp AppendText

    FileCheckFailed:
        mov rcx, [file_handle]
        call CloseHandle
        mov ecx, [failure_stage]
        call ExitProcess
        

    ; ------ открываем файл и проверяем, есть ли введённая строка в файле < конец кода > ------


    ; ------ добавляем BOM в файл < начало кода > ------
    AddBOMToFile:
        ; Файл только что создан — записать BOM UTF-16LE.
        mov rcx, [file_handle]
        lea rdx, [utf16_bom]
        mov r8d, 2
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteFile
        test eax, eax
        jz .close_fail
        jmp AppendText

        .close_fail:
            mov rcx, [file_handle]
            call CloseHandle
            jmp .fail

        .fail:
            mov ecx, 6                      ; код завершения 6
            call ExitProcess

    ; ------ добавляем BOM в файл < конец кода > ------
    
    
    
    ; ------ дописываем введённую строку в конец файла < начало кода > ------   

    AppendText:
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
        jmp .fail

    .fail:
        mov ecx, 1                      ; код завершения 1
        call ExitProcess

   ; ------ дописываем введённую строку в конец файла < конец кода > ------
