﻿param ($installPath, $ToolsPath, $Package, $Project)

Function global:Render-RazorTemplate {

    #.SYNOPSIS    
    # Renders the specified Razor template.
    #
    #.DESCRIPTION
    # Renders the specified Razor template
    # with an optional model.
    #
    #.EXAMPLE
    # Render-RazorTemplate -Template "Hello World!"
    # Output: Hello World!
    #
    #.EXAMPLE
    # Render-RazorTemplate "<ul>@foreach(var i in Model){<li>@i</li>}</ul>" (0..3)
    # Output: <ul><li>0</li><li>1</li><li>2</li><li>3</li></ul>

    [CmdLetBinding()]
    param (
        #
        # A Razor template.
        #
        [Parameter(Mandatory=$true)]
        [string] $Template,
        #
        # A model to use in the template.
        #
        [Parameter()]
        [object] $Model = $null
    )
    
    process {
    
        $razorAssembly = 
            [AppDomain]::CurrentDomain.GetAssemblies() |
                ? { $_.FullName -match "^System.Web.Razor" }
    
        If ($razorAssembly -eq $null) {
            
            $razorSearchPath = Join-Path `
                -Path $PWD `
                -ChildPath packages\AspNetRazor.Core.*\lib\net40\System.Web.Razor.dll
                
            $razorPath = Get-ChildItem -Path $razorSearchPath |
                Select-Object -First 1 -ExpandProperty FullName
            
            If ($razorPath -ne $null) {
                Add-Type -Path $razorPath
            } Else {            
                throw "The System.Web.Razor assembly must be loaded."
            }
        }
    
        $ModelType = "dynamic"    
        $TemplateClassName = "t{0}" -f 
            ([System.IO.Path]::GetRandomFileName() -replace "\.", "")
        $TemplateBaseClassName = "t{0}" -f 
            ([System.IO.Path]::GetRandomFileName() -replace "\.", "")
        $TemplateNamespace = "Kkj.Templates"

        $templateBaseCode = @"
using System;
using System.Text;
using Microsoft.CSharp.RuntimeBinder;

namespace {2} {{

    public abstract class {1}
    {{
        protected {0} Model;
        private StringBuilder _sb = new StringBuilder();
        public abstract void Execute();
        public virtual void Write(object value)
        {{
            WriteLiteral(value);
        }}
        public virtual void WriteLiteral(object value)
        {{
            _sb.Append(value);
        }}
        public string Render ({0} model)
        {{
            Model = model;
            Execute();
            var res = _sb.ToString();
            _sb.Clear();
            return res;
        }}
    }}
}}
"@ -f $ModelType, $TemplateBaseClassName, $TemplateNamespace

        #
        # A Razor template.
        #
        $language = New-Object `
            -TypeName System.Web.Razor.CSharpRazorCodeLanguage
        $engineHost = New-Object `
            -TypeName System.Web.Razor.RazorEngineHost `
            -ArgumentList $language `
            -Property @{
                DefaultBaseClass = "{0}.{1}" -f 
                    $TemplateNamespace, $TemplateBaseClassName;
                DefaultClassName = $TemplateClassName;
                DefaultNamespace = $TemplateNamespace;
            }
        $engine = New-Object `
            -TypeName System.Web.Razor.RazorTemplateEngine `
            -ArgumentList $engineHost
        $stringReader = New-Object `
            -TypeName System.IO.StringReader `
            -ArgumentList $Template
        $code = $engine.GenerateCode($stringReader)

        #
        # Template compilation.
        #
        $stringWriter = New-Object -TypeName System.IO.StringWriter
        $compiler = New-Object `
            -TypeName Microsoft.CSharp.CSharpCodeProvider
        $compilerResult = $compiler.GenerateCodeFromCompileUnit(
            $code.GeneratedCode, $stringWriter, $null
        )
        $templateCode = 
            $templateBaseCode + "`n" + $stringWriter.ToString()
        Add-Type `
            -TypeDefinition $templateCode `
            -ReferencedAssemblies System.Core, Microsoft.CSharp
            
        #
        # Template execution.
        #
        $templateInstance = New-Object -TypeName `
            ("{0}.{1}" -f $TemplateNamespace, $TemplateClassName)
        $templateInstance.Render($Model)
    }
}