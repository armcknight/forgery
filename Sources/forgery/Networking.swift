import Foundation

public enum RequestError: Error, CustomStringConvertible {
    case clientError(Error)
    case httpError(URLResponse)
    case noData
    case invalidData
    case resultError
    
    public var description: String {
        switch self {
        case .clientError(let error): return "Request failed in client stack with error: \(error)."
        case .httpError(let response): return "Request failed with HTTP status \((response as! HTTPURLResponse).statusCode)."
        case .noData: return "Response contained no data."
        case .invalidData: return "Response data couldn't be decoded."
        case .resultError: return "The request completed successfully but a problem occurred returning the decoded response."
        }
    }
}

public func synchronouslyRequest<T: Decodable>(request: URLRequest) -> Result<T, RequestError> {
    var result: T?
    var requestError: RequestError?
    
    let group = DispatchGroup()
    group.enter()
    urlSession.dataTask(with: request) { data, response, error in
        defer {
            group.leave()
        }
        
        guard error == nil else {
            requestError = RequestError.clientError(error!)
            return
        }
        
        let status = (response as! HTTPURLResponse).statusCode
        
        guard status >= 200 && status < 300 else {
            requestError = RequestError.httpError(response!)
            return
        }
        
        guard let data else {
            requestError = RequestError.noData
            return
        }
        
        do {
            result = try jsonDecoder.decode(T.self, from: data)
        } catch {
            guard let responseDataString = String(data: data, encoding: .utf8) else {
                logger.warning("Response data can't be decoded to a string for debugging error from decoding response data from request to \(String(describing: request.url)) (original error: \(error)")
                requestError = RequestError.invalidData
                return
            }
            logger.error("Failed decoding API response from request to \(String(describing: request.url)): \(error) (string contents: \(responseDataString))")
            requestError = RequestError.invalidData
        }
    }.resume()
    group.wait()
    
    if let requestError {
        return .failure(requestError)
    }
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return .success(result)
}
