//
//  TableViewController.swift
//  AirbnbHomework-Huangtao
//
//  Created by happts on 2019/5/7.
//  Copyright © 2019 happts. All rights reserved.
//

import UIKit
import Alamofire
import CRRefresh
import SwiftyJSON

class TableViewController: UITableViewController,UISearchBarDelegate{
    
    // MARK: - Model
    struct RepoOwner {
        let avatar_url:String
        init(_ json:JSON) {
            avatar_url = json["avatar_url"].stringValue
        }
    }
    
    struct Repo {
        let name:String
        let id:Int
        let stargazers_count:Int
        let owner:RepoOwner
        var avatarImageData:Data?
        
        init(_ json:JSON) {
            name = json["name"].stringValue
            id = json["id"].intValue
            stargazers_count = json["stargazers_count"].intValue
            owner = RepoOwner(json["owner"])
        }
        
        func getImageData(completion:@escaping ((Bool,Data?)->Void)) {
            Alamofire.request(self.owner.avatar_url, method: .get).responseData { (response) in
                switch response.result {
                case .success(let value):
                    completion(true,value)
                case .failure(_):
                    completion(false,nil)
                }
            }
        }
    }
    
    class User {
        let name:String
        var repos:[Repo] = []
        var currentPage:Int = 0
        
        init(name:String) {
            self.name = name
        }
        
        func requestRepos(page:Int,completion: @escaping (Bool,[Repo]?)->Void ) {
            let url = "https://api.github.com/users/"+name+"/repos"
            let parameter = ["page":page]
            Alamofire.request(url, method: .get, parameters: parameter).responseJSON { (response) in
                switch response.result {
                case .success(let value):
                    let array = JSON(value).arrayValue
                    if array.isEmpty {
                        completion(false,[])
                        return
                    }
                    let repos = array.map({ (e) -> Repo in
                        return Repo(e)
                    })
                    self.currentPage = page
                    self.repos += repos
                    
                    completion(true,repos)
                case .failure(_):
                    return completion(false,nil)
                }
            }
        }
    }
    
    // MARK: - Cache LRU
    class Cache<T> {
        let cacheSize:Int
        private var nodeListHead:Node<T>?
        private var dic:[String:Node<T>] = [:]
        
        init(size:Int) {
            self.cacheSize = size
            self.nodeListHead = nil
        }
        
        class Node<T> {
            var value:T
            var key:String
            
            var next:Node<T>? = nil
            var pre:Node<T>? = nil
            
            init(key:String,value:T) {
                self.key = key
                self.value = value
            }
        }
        
        func get(key:String) -> T? {
            
            if dic[key] != nil {
                moveToHead(node: dic[key])
            }
            
            return dic[key]?.value
        }
        
        func set(key:String,value:T) {
            if dic[key] != nil {
                dic[key]?.value = value
                moveToHead(node: dic[key])
            }else {
                
                if dic.count >= self.cacheSize {
                    var p = nodeListHead!
                    dic[p.key] = nil
                    while(nodeListHead?.next != nil){
                        p = nodeListHead!.next!
                    }
                    p.pre?.next = nil
                    p.next?.pre = nil
                }
                let node = Node<T>(key: key, value: value)
                dic[key] = node
                moveToHead(node: node)
            }
        }
        
        private func moveToHead(node:Node<T>?) {
            node?.pre?.next = node?.next
            node?.next?.pre = node?.pre
            
            node?.next = nodeListHead
            nodeListHead?.pre = node
            
            nodeListHead = node
            nodeListHead?.pre = nil
        }
        
    
    }
    
    // MARK: - Cell
    let cellReuseIdentifier = "RepoCell"
    
    class RepoCell: UITableViewCell {
        
        var repoName:String? {
            set {
                self.textLabel?.text = newValue!
            }
            
            get {
                return self.textLabel?.text
            }
        }
        
        var starCount:Int? {
            set {
                self.starCountLabel.text = "\(newValue!)"
            }
            
            get {
                return Int(self.starCountLabel.text ?? "")
            }
        }
        
        var avatarImage:UIImage? {
            set {
                self.imageView?.image = newValue
            }
            
            get {
                return self.imageView?.image
            }
        }
        
        private let starCountLabel = UILabel()
        private let starImageView = { () -> UIView in
            let imageView = UIImageView(image: UIImage(named: "star"))
            imageView.frame = CGRect(x: 0, y: 0, width: 21, height: 21)
            imageView.contentMode = .scaleAspectFill
            return imageView
        }()
        
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: .default, reuseIdentifier: reuseIdentifier)
            self.imageView?.image = UIImage(named: "avatar")
            self.accessoryView = { ()->UIView in
                let stackView = UIStackView(arrangedSubviews: [starCountLabel,starImageView])
                stackView.axis = .horizontal
                stackView.alignment = .center
                return stackView
            }()
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func bind(repo:Repo) {
            repoName = repo.name
            starCount = repo.stargazers_count
            if let imagedata = repo.avatarImageData {
                avatarImage = UIImage(data: imagedata)
            }else {
                avatarImage = UIImage(named: "avatar")
            }
            self.tag = repo.id
            
            let size = (starCountLabel.text! as NSString).size(withAttributes: [NSAttributedString.Key.font:starCountLabel.font])
            starCountLabel.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            self.accessoryView?.frame = CGRect(x: 0, y: 0, width: starCountLabel.frame.width+starImageView.frame.width+6, height: starImageView.frame.height)
        }
    }

    
    // MARK: - TableView
    var cache = Cache<User>.init(size: 10)
    var currentUserName = "airbnb"
    var footerView:CRRefreshFooterView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(RepoCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        
        
        let searchBar = UISearchBar()
        searchBar.text = ""
        searchBar.placeholder = "please input username"
        searchBar.delegate = self
        self.tableView.tableHeaderView = searchBar
        searchBar.sizeToFit()
        
        footerView = tableView.cr.addFootRefresh(animator: NormalFooterAnimator()) {
            let user = self.cache.get(key: self.currentUserName)!
            user.requestRepos(page: user.currentPage+1, completion: { (result, _ ) in
                if result {
                    self.tableView.cr.endLoadingMore()
                    self.tableView.reloadData()
                }else {
                    self.tableView.cr.noticeNoMoreData()
                }
            })
            
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cache.get(key: currentUserName)?.repos.count ?? 0
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! RepoCell
        let user = cache.get(key: currentUserName)!
        cell.bind(repo: user.repos[indexPath.row])
        if user.repos[indexPath.row].avatarImageData == nil {
            user.repos[indexPath.row].getImageData { (result, imagedata) in
                if result {
                    user.repos[indexPath.row].avatarImageData = imagedata
                    (tableView.visibleCells.filter{$0.tag == user.repos[indexPath.row].id}.first as! RepoCell?)?.avatarImage = UIImage(data: imagedata!)
                }
            }
        }
        return cell
    }
    

    // MARK: - SearchBar Delegate
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.footerView.resetNoMoreData()
        
        searchBar.resignFirstResponder()
        let name = searchBar.text ?? ""
        if cache.get(key: name) != nil {
            self.currentUserName = name
            self.tableView.reloadData()
        }else {
            let user = User(name: name)
            user.requestRepos(page: user.currentPage+1) { (result,  _ ) in
                if result {
                    self.cache.set(key: user.name, value: user)
                }else {
                    self.footerView.noticeNoMoreData()
                }
                self.currentUserName = user.name
                self.tableView.reloadData()
            }
        }
    }
}
