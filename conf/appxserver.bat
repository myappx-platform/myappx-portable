@Echo off

CALL utils\myEnvironment.bat Server

@if not "%JAVA_HOME%" == "" goto JAVA_HOME_OK
@Set JAVA=java
@Echo JAVA_HOME is not set.
@Echo You may not be able to start the server
@Echo Set JAVA_HOME to the directory of your local JDK.
goto START

:JAVA_HOME_OK
@Set JAVA=%JAVA_HOME%\bin\java.exe

:START
@Echo =======================================
@Echo Starting Portable AppxServer ...
@Echo =======================================

FOR %%c in (plugins\org.eclipse.equinox.launcher_1.*.jar) DO set JARFILE=%%c

@Set VMOPTS=%VMOPTS% -Duser.timezone=Asia/Shanghai
@Set VMOPTS=%VMOPTS% -Dorg.osgi.framework.bootdelegation=sun.security.ssl
@Set VMOPTS=%VMOPTS% -Dosgi.compatibility.bootdelegation=true
@Set VMOPTS=%VMOPTS% -Djetty.home=jettyhome
@Set VMOPTS=%VMOPTS% -Djetty.base=jettyhome
@Set VMOPTS=%VMOPTS% -Djetty.etc.config.urls=etc/jetty-bytebufferpool.xml,etc/jetty-threadpool.xml,etc/jetty.xml,etc/jetty-http.xml,etc/jetty-deploy.xml,etc/jetty-ssl-context.xml,etc/jetty-ssl.xml,etc/jetty-https.xml,etc/jetty-http-forwarded.xml
@Set VMOPTS=%VMOPTS% -Dorg.apache.cxf.osgi.http.transport.disable=true
@Set VMOPTS=%VMOPTS% -Dosgi.console=localhost:12612
@Set VMOPTS=%VMOPTS% -Dmail.mime.encodefilename=true
@Set VMOPTS=%VMOPTS% -Dmail.mime.decodefilename=true
@Set VMOPTS=%VMOPTS% -Dmail.mime.encodeparameters=true
@Set VMOPTS=%VMOPTS% -Dmail.mime.decodeparameters=true
@Set VMOPTS=%VMOPTS% -Dorg.eclipse.jetty.ee8.annotations.AnnotationParser.LEVEL=OFF
@Set VMOPTS=%VMOPTS% -Dorg.eclipse.jetty.ee8.osgi.annotations.AnnotationParser.LEVEL=OFF
@Set VMOPTS=%VMOPTS% -DIDEMPIERE_EXTENSION_REPOSITORY=http://127.0.0.1:18080/myappx-extension-repository

@"%JAVA%" %IDEMPIERE_JAVA_OPTIONS% %VMOPTS% -jar %JARFILE% -application org.adempiere.server.application
