import { NextRequest, NextResponse } from "next/server";

// Proxy all auth requests to the backend
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ auth: string[] }> }
) {
  const resolvedParams = await params;
  return proxyAuthRequest(request, resolvedParams.auth);
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ auth: string[] }> }
) {
  const resolvedParams = await params;
  return proxyAuthRequest(request, resolvedParams.auth);
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ auth: string[] }> }
) {
  const resolvedParams = await params;
  return proxyAuthRequest(request, resolvedParams.auth);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ auth: string[] }> }
) {
  const resolvedParams = await params;
  return proxyAuthRequest(request, resolvedParams.auth);
}

async function proxyAuthRequest(request: NextRequest, authPath: string[]) {
  const backendUrl = process.env.NEXT_PUBLIC_API_URL || 'https://metamcp-backend-555166161772.us-central1.run.app';
  const targetPath = authPath.join('/');
  const targetUrl = `${backendUrl}/api/auth/${targetPath}`;
  
  // Get search params from the request
  const searchParams = request.nextUrl.searchParams.toString();
  const fullTargetUrl = searchParams ? `${targetUrl}?${searchParams}` : targetUrl;
  
  try {
    const headers = new Headers();
    
    // Copy important headers from the original request
    const headersToProxy = [
      'content-type',
      'authorization',
      'cookie',
      'user-agent',
      'accept',
      'accept-language',
    ];
    
    for (const headerName of headersToProxy) {
      const headerValue = request.headers.get(headerName);
      if (headerValue) {
        headers.set(headerName, headerValue);
      }
    }
    
    // Prepare the request body if it exists
    let body: string | undefined;
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      try {
        body = await request.text();
      } catch {
        // If body can't be read, continue without it
      }
    }
    
    // Make the request to the backend
    const response = await fetch(fullTargetUrl, {
      method: request.method,
      headers,
      body,
    });
    
    // Create response headers
    const responseHeaders = new Headers();
    
    // Copy response headers from backend, except for some that might cause issues
    const headersToForward = [
      'content-type',
      'set-cookie',
      'cache-control',
      'expires',
      'etag',
      'last-modified',
    ];
    
    for (const headerName of headersToForward) {
      const headerValue = response.headers.get(headerName);
      if (headerValue) {
        responseHeaders.set(headerName, headerValue);
      }
    }
    
    // Get response body
    const responseBody = await response.text();
    
    return new NextResponse(responseBody, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders,
    });
    
  } catch (error) {
    console.error('Auth proxy error:', error);
    return new NextResponse(
      JSON.stringify({ error: 'Auth proxy failed' }),
      {
        status: 500,
        headers: { 'content-type': 'application/json' },
      }
    );
  }
}